
`timescale 1ns/1ps

module tb_mac_array;

    parameter ARRAY_SIZE = 4;
    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 32;

    reg clk;
    reg rst;
    reg en;
    reg clear;

    reg [(ARRAY_SIZE*DATA_WIDTH)-1:0] a_in;
    reg [(ARRAY_SIZE*DATA_WIDTH)-1:0] b_in;

    wire [(ARRAY_SIZE*ARRAY_SIZE*ACC_WIDTH)-1:0] c_out;

    reg signed [DATA_WIDTH-1:0] matrix_a [0:15];
    reg signed [DATA_WIDTH-1:0] matrix_b [0:15];

    reg signed [ACC_WIDTH-1:0] expected [0:15];
    reg signed [ACC_WIDTH-1:0] actual;

    integer i, j, k, t;
    integer passed;
    integer failed;

    // Device under test
    mac_array #(
        .ARRAY_SIZE(ARRAY_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .clear(clear),
        .a_in(a_in),
        .b_in(b_in),
        .c_out(c_out)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Reset the array
    task reset_array;
        begin
            @(negedge clk);

            rst   = 1;
            en    = 0;
            clear = 0;
            a_in  = 0;
            b_in  = 0;

            @(posedge clk);
            #1;

            @(negedge clk);
            rst = 0;
        end
    endtask

    // Calculate expected matrix multiplication
    task calculate_expected;
        integer row, col, n;
        begin
            for (row = 0; row < 4; row = row + 1) begin
                for (col = 0; col < 4; col = col + 1) begin

                    expected[row*4+col] = 0;

                    for (n = 0; n < 4; n = n + 1) begin
                        expected[row*4+col] =
                            expected[row*4+col] +
                            matrix_a[row*4+n] *
                            matrix_b[n*4+col];
                    end

                end
            end
        end
    endtask

    // Feed staggered inputs into the systolic array
    task run_matrix;
        integer cycle;
        integer row, col;
        integer a_index, b_index;

        begin

            reset_array;
            calculate_expected;

            // 4x4 multiplication requires 10 compute cycles
            for (cycle = 0; cycle < 10; cycle = cycle + 1) begin

                @(negedge clk);

                en    = 1;
                clear = 0;
                a_in  = 0;
                b_in  = 0;

                // Feed matrix A by row
                for (row = 0; row < 4; row = row + 1) begin

                    a_index = cycle - row;

                    if (a_index >= 0 && a_index < 4)
                        a_in[row*DATA_WIDTH +: DATA_WIDTH]
                            = matrix_a[row*4+a_index];

                end

                // Feed matrix B by column
                for (col = 0; col < 4; col = col + 1) begin

                    b_index = cycle - col;

                    if (b_index >= 0 && b_index < 4)
                        b_in[col*DATA_WIDTH +: DATA_WIDTH]
                            = matrix_b[b_index*4+col];

                end

                @(posedge clk);
                #1;

            end

            @(negedge clk);
            en   = 0;
            a_in = 0;
            b_in = 0;

        end
    endtask

    // Check all 16 matrix outputs
    task check_results;
        integer row, col;

        begin
            for (row = 0; row < 4; row = row + 1) begin
                for (col = 0; col < 4; col = col + 1) begin

                    actual = c_out[
                        (row*4+col)*ACC_WIDTH +: ACC_WIDTH
                    ];

                    if (actual !== expected[row*4+col]) begin

                        $display(
                            "[FAIL] C[%0d][%0d] = %0d Expected = %0d",
                            row, col, actual,
                            expected[row*4+col]
                        );

                        failed = failed + 1;

                    end else begin

                        $display(
                            "[PASS] C[%0d][%0d] = %0d",
                            row, col, actual
                        );

                        passed = passed + 1;

                    end
                end
            end
        end
    endtask

    // Main test sequence
    initial begin

        $dumpfile("mac_array_wave.vcd");
        $dumpvars(0, tb_mac_array);

        rst    = 1;
        en     = 0;
        clear  = 0;
        a_in   = 0;
        b_in   = 0;

        passed = 0;
        failed = 0;

        $display("========================================");
        $display(" GraphCore 4x4 MAC Array Testbench");
        $display("========================================");

        // ====================================
        // TEST 1: Reset
        // ====================================

        $display("\nTEST 1: Reset");

        reset_array;

        if (c_out === 0) begin
            $display("[PASS] All accumulators reset");
            passed = passed + 1;
        end else begin
            $display("[FAIL] Reset");
            failed = failed + 1;
        end

        // ====================================
        // TEST 2: All ones
        // Expected: Every output equals 4
        // ====================================

        $display("\nTEST 2: All ones");

        for (i = 0; i < 16; i = i + 1) begin
            matrix_a[i] = 1;
            matrix_b[i] = 1;
        end

        run_matrix;
        check_results;

        // ====================================
        // TEST 3: Identity matrix
        // Expected: C = A
        // ====================================

        $display("\nTEST 3: Identity matrix");

        for (i = 0; i < 16; i = i + 1) begin
            matrix_a[i] = i + 1;
            matrix_b[i] = 0;
        end

        for (i = 0; i < 4; i = i + 1)
            matrix_b[i*4+i] = 1;

        run_matrix;
        check_results;

        // ====================================
        // TEST 4: General matrix multiplication
        // ====================================

        $display("\nTEST 4: General matrix multiplication");

        for (i = 0; i < 16; i = i + 1) begin
            matrix_a[i] = i + 1;
            matrix_b[i] = 16 - i;
        end

        run_matrix;
        check_results;

        // ====================================
        // TEST 5: Signed negative operands
        // ====================================

        $display("\nTEST 5: Signed multiplication");

        for (i = 0; i < 16; i = i + 1) begin
            matrix_a[i] = i - 8;
            matrix_b[i] = 4 - i;
        end

        run_matrix;
        check_results;

        // ====================================
        // TEST 6: Signed boundary values
        // ====================================

        $display("\nTEST 6: Signed boundary values");

        for (i = 0; i < 16; i = i + 1) begin
            matrix_a[i] = -128;
            matrix_b[i] = 127;
        end

        run_matrix;
        check_results;

        // ====================================
        // TEST 7: Enable hold
        // ====================================

        $display("\nTEST 7: Enable hold");

        @(negedge clk);

        en   = 0;
        a_in = 32'h01020304;
        b_in = 32'h05060708;

        repeat (4) @(posedge clk);
        #1;

        check_results;

        // ====================================
        // TEST 8: Clear accumulators
        // ====================================

        $display("\nTEST 8: Clear accumulators");

        @(negedge clk);

        clear = 1;
        en    = 1;

        @(posedge clk);
        #1;

        if (c_out === 0) begin
            $display("[PASS] All accumulators cleared");
            passed = passed + 1;
        end else begin
            $display("[FAIL] Clear");
            failed = failed + 1;
        end

        // ====================================
        // Final results
        // ====================================

        $display("\n========================================");
        $display(" Test Results");
        $display("========================================");
        $display(" PASSED: %0d", passed);
        $display(" FAILED: %0d", failed);
        $display("========================================");

        if (failed == 0)
            $display("ALL MAC ARRAY TESTS PASSED");
        else
            $fatal(1, "MAC ARRAY VERIFICATION FAILED");

        $finish;

    end

endmodule
