
`timescale 1ns/1ps

module tb_mean_normalizer;

    parameter FEATURE_DIM = 8;
    parameter DATA_WIDTH  = 8;
    parameter ACC_WIDTH   = 32;
    parameter COUNT_WIDTH = 9;

    reg clk;
    reg rst;
    reg start;

    reg [(FEATURE_DIM*ACC_WIDTH)-1:0] sum_in;
    reg [COUNT_WIDTH-1:0] neighbor_count;

    wire [(FEATURE_DIM*DATA_WIDTH)-1:0] mean_out;
    wire busy;
    wire done;

    reg signed [DATA_WIDTH-1:0] expected;
    reg signed [DATA_WIDTH-1:0] actual;
    reg signed [ACC_WIDTH-1:0] feature_sum;

    integer passed;
    integer failed;
    integer i;

    // Device under test
    mean_normalizer #(
        .FEATURE_DIM(FEATURE_DIM),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .COUNT_WIDTH(COUNT_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .sum_in(sum_in),
        .neighbor_count(neighbor_count),
        .mean_out(mean_out),
        .busy(busy),
        .done(done)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Check a control condition
    task check_control;
        input condition;
        input [8*80-1:0] description;
        begin
            if (condition === 1'b1) begin
                $display("[PASS] %0s", description);
                passed = passed + 1;
            end else begin
                $display("[FAIL] %0s", description);
                failed = failed + 1;
            end
        end
    endtask

    // Reset DUT
    task reset_dut;
        begin
            @(negedge clk);
            rst   = 1;
            start = 0;

            @(posedge clk);
            #1;

            @(negedge clk);
            rst = 0;
        end
    endtask

    // Begin normalization
    task start_normalization;
        begin
            @(negedge clk);
            start = 1;

            @(posedge clk);
            #1;

            check_control(
                busy && !done,
                "Busy asserted after start"
            );

            @(negedge clk);
            start = 0;
        end
    endtask

    // Wait for normalization to finish
    task wait_for_done;
        integer cycles;
        begin
            cycles = 0;

            while (done !== 1'b1 &&
                   cycles < FEATURE_DIM + 5) begin

                @(posedge clk);
                #1;
                cycles = cycles + 1;

            end

            check_control(
                done === 1'b1,
                "Normalization completed"
            );

            check_control(
                busy === 1'b0,
                "Busy deasserted after completion"
            );

            check_control(
                cycles == FEATURE_DIM + 1,
                "Correct computation latency"
            );
        end
    endtask

    // Check every normalized feature
    task check_results;
        integer j;
        integer divisor;

        begin
            divisor = neighbor_count;

            for (j = 0; j < FEATURE_DIM; j = j + 1)
            begin

                feature_sum = $signed(
                    sum_in[j*ACC_WIDTH +: ACC_WIDTH]
                );

                if (divisor == 0)
                    expected = 0;
                else
                    expected = feature_sum / divisor;

                actual = $signed(
                    mean_out[j*DATA_WIDTH +: DATA_WIDTH]
                );

                if (actual !== expected) begin

                    $display(
                        "[FAIL] Feature %0d: Sum=%0d Count=%0d Actual=%0d Expected=%0d",
                        j, feature_sum, divisor,
                        actual, expected
                    );

                    failed = failed + 1;

                end else begin

                    $display(
                        "[PASS] Feature %0d: %0d / %0d = %0d",
                        j, feature_sum, divisor, actual
                    );

                    passed = passed + 1;

                end
            end
        end
    endtask

    // Run one complete normalization operation
    task run_test;
        begin
            start_normalization;
            wait_for_done;
            check_results;

            @(posedge clk);
            #1;

            check_control(
                done === 1'b0,
                "Done is a one-cycle pulse"
            );
        end
    endtask

    // Main test sequence
    initial begin

        $dumpfile("mean_normalizer_wave.vcd");
        $dumpvars(0, tb_mean_normalizer);

        rst            = 1;
        start          = 0;
        sum_in         = 0;
        neighbor_count = 0;

        passed = 0;
        failed = 0;

        $display("========================================");
        $display(" GraphCore Mean Normalizer Testbench");
        $display("========================================");

        // ====================================
        // TEST 1: Reset
        // ====================================

        $display("\nTEST 1: Reset");

        reset_dut;

        check_control(
            mean_out === 0,
            "Output registers reset"
        );

        check_control(
            busy === 1'b0,
            "Busy reset"
        );

        check_control(
            done === 1'b0,
            "Done reset"
        );

        // ====================================
        // TEST 2: Positive features
        // ====================================

        $display("\nTEST 2: Positive features");

        neighbor_count = 4;

        sum_in = {
            32'd32, 32'd28,
            32'd24, 32'd20,
            32'd16, 32'd12,
            32'd8,  32'd4
        };

        run_test;

        // ====================================
        // TEST 3: Negative features
        // ====================================

        $display("\nTEST 3: Negative features");

        neighbor_count = 4;

        sum_in = {
            -32'sd32, -32'sd28,
            -32'sd24, -32'sd20,
            -32'sd16, -32'sd12,
            -32'sd8,  -32'sd4
        };

        run_test;

        // ====================================
        // TEST 4: Mixed signed features
        // ====================================

        $display("\nTEST 4: Mixed signed features");

        neighbor_count = 4;

        sum_in = {
             32'sd24,  32'sd16,
            -32'sd32,  32'sd48,
             32'sd44,  32'sd36,
            -32'sd28,  32'sd20
        };

        run_test;

        // ====================================
        // TEST 5: Integer truncation
        // ====================================

        $display("\nTEST 5: Integer truncation");

        neighbor_count = 3;

        sum_in = {
             32'sd11, -32'sd11,
             32'sd10, -32'sd10,
             32'sd7,  -32'sd7,
             32'sd2,  -32'sd2
        };

        run_test;

        // ====================================
        // TEST 6: Zero neighbors
        // ====================================

        $display("\nTEST 6: Zero neighbors");

        neighbor_count = 0;

        sum_in = {
             32'sd100, -32'sd100,
             32'sd50,  -32'sd50,
             32'sd25,  -32'sd25,
             32'sd10,  -32'sd10
        };

        run_test;

        // ====================================
        // TEST 7: One neighbor
        // ====================================

        $display("\nTEST 7: One neighbor");

        neighbor_count = 1;

        sum_in = {
             32'sd127, -32'sd128,
             32'sd64,  -32'sd64,
             32'sd32,  -32'sd32,
             32'sd1,   -32'sd1
        };

        run_test;

        // ====================================
        // TEST 8: Maximum neighbor count
        // ====================================

        $display("\nTEST 8: 256 neighbors");

        neighbor_count = 9'd256;

        sum_in = {
             32'sd32512, -32'sd32768,
             32'sd25600, -32'sd25600,
             32'sd16384, -32'sd16384,
             32'sd256,   -32'sd256
        };

        run_test;

        // ====================================
        // TEST 9: Zero feature sums
        // ====================================

        $display("\nTEST 9: Zero feature sums");

        neighbor_count = 5;
        sum_in = 0;

        run_test;

        // ====================================
        // TEST 10: Reset during computation
        // ====================================

        $display("\nTEST 10: Reset during computation");

        neighbor_count = 4;

        for (i = 0; i < FEATURE_DIM; i = i + 1)
            sum_in[i*ACC_WIDTH +: ACC_WIDTH] = 40;

        start_normalization;

        repeat (3) @(posedge clk);
        #1;

        check_control(
            busy === 1'b1,
            "Computation active before reset"
        );

        reset_dut;

        check_control(
            busy === 1'b0,
            "Reset cancels computation"
        );

        check_control(
            done === 1'b0,
            "Done cleared after reset"
        );

        check_control(
            mean_out === 0,
            "Feature outputs cleared after reset"
        );

        // ====================================
        // TEST 11: Restart after reset
        // ====================================

        $display("\nTEST 11: Restart after reset");

        neighbor_count = 2;

        for (i = 0; i < FEATURE_DIM; i = i + 1)
            sum_in[i*ACC_WIDTH +: ACC_WIDTH] =
                (i + 1) * 10;

        run_test;

        // Final summary
        $display("\n========================================");
        $display(" Test Results");
        $display("========================================");
        $display(" PASSED: %0d", passed);
        $display(" FAILED: %0d", failed);
        $display("========================================");

        if (failed == 0)
            $display("ALL MEAN NORMALIZER TESTS PASSED");
        else
            $fatal(1, "MEAN NORMALIZER VERIFICATION FAILED");

        $finish;
    end

    // Simulation timeout protection
    initial begin
        #100000;
        $fatal(1, "Simulation timeout");
    end

endmodule
