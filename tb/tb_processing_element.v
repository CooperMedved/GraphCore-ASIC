
`timescale 1ns/1ps

module tb_processing_element;

    parameter DATA_WIDTH = 8;
    parameter ACC_WIDTH  = 32;

    reg clk;
    reg rst;
    reg en;
    reg clear;

    reg signed [DATA_WIDTH-1:0] a_in;
    reg signed [DATA_WIDTH-1:0] b_in;

    wire signed [DATA_WIDTH-1:0] a_out;
    wire signed [DATA_WIDTH-1:0] b_out;
    wire signed [ACC_WIDTH-1:0] acc_out;

    integer tests_passed;
    integer tests_failed;
    integer expected_acc;

    // Device under test
    processing_element #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .clear(clear),
        .a_in(a_in),
        .b_in(b_in),
        .a_out(a_out),
        .b_out(b_out),
        .acc_out(acc_out)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Check all registered outputs
    task check_outputs;
        input signed [DATA_WIDTH-1:0] exp_a;
        input signed [DATA_WIDTH-1:0] exp_b;
        input signed [ACC_WIDTH-1:0] exp_acc;
        begin
            if (a_out !== exp_a ||
                b_out !== exp_b ||
                acc_out !== exp_acc) begin

                $display("[FAIL] Time=%0t | A=%0d expected=%0d | B=%0d expected=%0d | ACC=%0d expected=%0d",
                         $time, a_out, exp_a,
                         b_out, exp_b,
                         acc_out, exp_acc);

                tests_failed = tests_failed + 1;
            end else begin
                $display("[PASS] Time=%0t | A=%0d B=%0d ACC=%0d",
                         $time, a_out, b_out, acc_out);

                tests_passed = tests_passed + 1;
            end
        end
    endtask

    // Apply controls and data before the next rising edge
    task apply_cycle;
        input test_rst;
        input test_clear;
        input test_en;
        input signed [DATA_WIDTH-1:0] test_a;
        input signed [DATA_WIDTH-1:0] test_b;
        begin
            @(negedge clk);
            rst   = test_rst;
            clear = test_clear;
            en    = test_en;
            a_in  = test_a;
            b_in  = test_b;

            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        $dumpfile("pe_wave.vcd");
        $dumpvars(0, tb_processing_element);

        tests_passed = 0;
        tests_failed = 0;
        expected_acc = 0;

        rst = 1;
        clear = 0;
        en = 0;
        a_in = 0;
        b_in = 0;

        $display("========================================");
        $display(" GraphCore Processing Element Testbench");
        $display("========================================");

        // Test 1: Reset
        $display("\nTEST 1: Reset");
        apply_cycle(1, 0, 0, 0, 0);
        check_outputs(0, 0, 0);

        // Test 2: Positive multiplication
        $display("\nTEST 2: Positive multiplication");
        apply_cycle(0, 0, 1, 2, 3);
        check_outputs(2, 3, 6);

        // Test 3: Accumulation
        $display("\nTEST 3: Accumulation");
        apply_cycle(0, 0, 1, 4, 5);
        check_outputs(4, 5, 26);

        // Test 4: Negative multiplication
        $display("\nTEST 4: Negative multiplication");
        apply_cycle(0, 0, 1, -3, 4);
        check_outputs(-3, 4, 14);

        // Test 5: Two negative operands
        $display("\nTEST 5: Negative operands");
        apply_cycle(0, 0, 1, -2, -5);
        check_outputs(-2, -5, 24);

        // Test 6: Enable disabled, hold state
        $display("\nTEST 6: Hold state");
        apply_cycle(0, 0, 0, 5, 5);
        check_outputs(-2, -5, 24);

        // Test 7: Clear accumulator only
        $display("\nTEST 7: Clear accumulator");
        apply_cycle(0, 1, 0, 7, 8);
        check_outputs(-2, -5, 0);

        // Test 8: Signed boundary values
        $display("\nTEST 8: Signed boundary values");
        apply_cycle(0, 0, 1, -128, -128);
        check_outputs(-128, -128, 16384);

        // Test 9: Reset overrides clear and enable
        $display("\nTEST 9: Reset priority");
        apply_cycle(1, 1, 1, 20, 30);
        check_outputs(0, 0, 0);

        // Test 10: Clear overrides enable
        $display("\nTEST 10: Clear priority");
        apply_cycle(0, 0, 1, 3, 4);
        check_outputs(3, 4, 12);

        apply_cycle(0, 1, 1, 9, 9);
        check_outputs(3, 4, 0);

        // Test 11: Resume after clear
        $display("\nTEST 11: Resume accumulation");
        apply_cycle(0, 0, 1, 7, -3);
        check_outputs(7, -3, -21);

        // Final summary
        $display("\n========================================");
        $display(" Test Results");
        $display("========================================");
        $display(" PASSED: %0d", tests_passed);
        $display(" FAILED: %0d", tests_failed);
        $display("========================================");

        if (tests_failed == 0) begin
            $display("ALL PROCESSING ELEMENT TESTS PASSED");
        end else begin
            $display("PROCESSING ELEMENT TESTS FAILED");
            $fatal(1, "Verification failure");
        end

        $finish;
    end

endmodule
