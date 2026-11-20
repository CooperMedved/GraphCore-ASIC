
`timescale 1ns/1ps

module tb_aggregator;

    parameter FEATURE_DIM = 8;
    parameter DATA_WIDTH  = 8;
    parameter ACC_WIDTH   = 32;
    parameter COUNT_WIDTH = 9;

    reg clk;
    reg rst;
    reg en;
    reg clear;

    reg [(FEATURE_DIM*DATA_WIDTH)-1:0] feature_in;

    wire [(FEATURE_DIM*ACC_WIDTH)-1:0] sum_out;
    wire [COUNT_WIDTH-1:0] neighbor_count;

    reg signed [ACC_WIDTH-1:0] expected [0:FEATURE_DIM-1];
    reg signed [ACC_WIDTH-1:0] actual;

    integer expected_count;
    integer passed;
    integer failed;
    integer i;

    // Device under test
    aggregator #(
        .FEATURE_DIM(FEATURE_DIM),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .COUNT_WIDTH(COUNT_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .clear(clear),
        .feature_in(feature_in),
        .sum_out(sum_out),
        .neighbor_count(neighbor_count)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Apply inputs and update reference model
    task apply_cycle;
        input test_rst;
        input test_clear;
        input test_en;
        input [(FEATURE_DIM*DATA_WIDTH)-1:0] features;

        integer j;

        begin
            @(negedge clk);

            rst        = test_rst;
            clear      = test_clear;
            en         = test_en;
            feature_in = features;

            if (test_rst || test_clear) begin

                for (j = 0; j < FEATURE_DIM; j = j + 1)
                    expected[j] = 0;

                expected_count = 0;

            end else if (test_en) begin

                for (j = 0; j < FEATURE_DIM; j = j + 1)
                    expected[j] = expected[j] +
                        $signed(features[j*DATA_WIDTH
                                        +: DATA_WIDTH]);

                expected_count = expected_count + 1;

            end

            @(posedge clk);
            #1;
        end
    endtask

    // Check all feature sums and neighbor count
    task check_results;
        integer j;

        begin
            for (j = 0; j < FEATURE_DIM; j = j + 1) begin

                actual = sum_out[j*ACC_WIDTH +: ACC_WIDTH];

                if (actual !== expected[j]) begin

                    $display(
                        "[FAIL] ACC[%0d] = %0d Expected = %0d",
                        j, actual, expected[j]
                    );

                    failed = failed + 1;

                end else begin

                    $display(
                        "[PASS] ACC[%0d] = %0d",
                        j, actual
                    );

                    passed = passed + 1;

                end
            end

            if (neighbor_count !== expected_count) begin

                $display(
                    "[FAIL] Count = %0d Expected = %0d",
                    neighbor_count, expected_count
                );

                failed = failed + 1;

            end else begin

                $display(
                    "[PASS] Neighbor count = %0d",
                    neighbor_count
                );

                passed = passed + 1;

            end
        end
    endtask

    // Main test sequence
    initial begin

        $dumpfile("aggregator_wave.vcd");
        $dumpvars(0, tb_aggregator);

        rst        = 1;
        en         = 0;
        clear      = 0;
        feature_in = 0;

        passed = 0;
        failed = 0;
        expected_count = 0;

        for (i = 0; i < FEATURE_DIM; i = i + 1)
            expected[i] = 0;

        $display("========================================");
        $display(" GraphCore Aggregator Testbench");
        $display("========================================");

        // TEST 1: Reset
        $display("\nTEST 1: Reset");

        apply_cycle(1, 0, 0, 64'h0);
        check_results;

        // TEST 2: First neighbor
        $display("\nTEST 2: First neighbor");

        apply_cycle(0, 0, 1, 64'h0807060504030201);
        check_results;

        // TEST 3: Second neighbor
        $display("\nTEST 3: Second neighbor");

        apply_cycle(0, 0, 1, 64'h100E0C0A08060402);
        check_results;

        // TEST 4: Third neighbor
        $display("\nTEST 4: Third neighbor");

        apply_cycle(0, 0, 1, 64'h1815120F0C090603);
        check_results;

        // TEST 5: Negative features
        $display("\nTEST 5: Negative features");

        apply_cycle(0, 0, 1, {
            -8'sd8, -8'sd7, -8'sd6, -8'sd5,
            -8'sd4, -8'sd3, -8'sd2, -8'sd1
        });

        check_results;

        // TEST 6: Enable disabled
        $display("\nTEST 6: Hold state");

        apply_cycle(0, 0, 0, 64'hFFFFFFFFFFFFFFFF);
        check_results;

        // TEST 7: Clear
        $display("\nTEST 7: Clear");

        apply_cycle(0, 1, 0, 64'h0);
        check_results;

        // TEST 8: Mixed signed features
        $display("\nTEST 8: Mixed signed features");

        apply_cycle(0, 0, 1, {
            8'sd127, -8'sd128,
            8'sd100, -8'sd100,
            8'sd50,  -8'sd50,
            8'sd1,   -8'sd1
        });

        check_results;

        // TEST 9: Clear overrides enable
        $display("\nTEST 9: Clear priority");

        apply_cycle(0, 1, 1, 64'h0101010101010101);
        check_results;

        // TEST 10: Maximum neighbor count
        $display("\nTEST 10: 256 neighbors");

        for (i = 0; i < 256; i = i + 1) begin
            apply_cycle(0, 0, 1, 64'h0101010101010101);
        end

        check_results;

        // TEST 11: Maximum negative accumulation
        $display("\nTEST 11: Negative accumulation");

        apply_cycle(0, 1, 0, 64'h0);

        for (i = 0; i < 256; i = i + 1) begin
            apply_cycle(0, 0, 1, 64'h8080808080808080);
        end

        check_results;

        // TEST 12: Reset overrides all controls
        $display("\nTEST 12: Reset priority");

        apply_cycle(1, 1, 1, 64'hFFFFFFFFFFFFFFFF);
        check_results;

        // Final summary
        $display("\n========================================");
        $display(" Test Results");
        $display("========================================");
        $display(" PASSED: %0d", passed);
        $display(" FAILED: %0d", failed);
        $display("========================================");

        if (failed == 0) begin
            $display("ALL AGGREGATOR TESTS PASSED");
        end else begin
            $fatal(1, "AGGREGATOR VERIFICATION FAILED");
        end

        $finish;

    end

endmodule
