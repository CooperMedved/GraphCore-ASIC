
`timescale 1ns/1ps

module tb_quantizer;

    parameter FEATURE_DIM = 8;
    parameter ACC_WIDTH = 32;
    parameter DATA_WIDTH = 8;
    parameter SHIFT_WIDTH = 5;

    reg [(FEATURE_DIM*ACC_WIDTH)-1:0] data_in;
    reg [SHIFT_WIDTH-1:0] shift;

    wire [(FEATURE_DIM*DATA_WIDTH)-1:0] data_out;

    integer passed;
    integer failed;
    integer i;
    integer j;
    integer s;
    integer seed;

    // Device under test
    quantizer #(
        .FEATURE_DIM(FEATURE_DIM),
        .ACC_WIDTH(ACC_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SHIFT_WIDTH(SHIFT_WIDTH)
    ) dut (
        .data_in(data_in),
        .shift(shift),
        .data_out(data_out)
    );

    // Independent mathematical reference model
    function signed [DATA_WIDTH-1:0] reference_quant;
        input signed [ACC_WIDTH-1:0] value;
        input [SHIFT_WIDTH-1:0] shift_amount;

        reg signed [63:0] extended_value;
        reg signed [63:0] divisor;
        reg signed [63:0] scaled;

        begin

            extended_value = value;
            divisor = 64'sd1 << shift_amount;

            // Division normally truncates toward zero.
            // Correct negative values to match arithmetic
            // right-shift behavior (floor division).

            scaled = extended_value / divisor;

            if (extended_value < 0 &&
                extended_value % divisor != 0)
                scaled = scaled - 1;

            // Signed INT8 saturation
            if (scaled > 127)
                reference_quant = 127;
            else if (scaled < -128)
                reference_quant = -128;
            else
                reference_quant = scaled[DATA_WIDTH-1:0];

        end
    endfunction

    // Verify every quantization lane
    task check_vector;

        integer k;

        reg signed [ACC_WIDTH-1:0] input_value;
        reg signed [DATA_WIDTH-1:0] actual_value;
        reg signed [DATA_WIDTH-1:0] expected_value;

        begin

            // Allow combinational logic to settle
            #1;

            for (k = 0; k < FEATURE_DIM; k = k + 1) begin

                input_value =
                    $signed(
                        data_in[k*ACC_WIDTH +: ACC_WIDTH]
                    );

                actual_value =
                    $signed(
                        data_out[k*DATA_WIDTH +: DATA_WIDTH]
                    );

                expected_value =
                    reference_quant(input_value, shift);

                if (actual_value === expected_value) begin

                    $display(
                        "[PASS] Lane=%0d Input=%0d Shift=%0d Output=%0d",
                        k, input_value, shift, actual_value
                    );

                    passed = passed + 1;

                end else begin

                    $display(
                        "[FAIL] Lane=%0d Input=%0d Shift=%0d Output=%0d Expected=%0d",
                        k, input_value, shift,
                        actual_value, expected_value
                    );

                    failed = failed + 1;

                end
            end
        end
    endtask

    // Main test sequence
    initial begin

        $dumpfile("quantizer_wave.vcd");
        $dumpvars(0, tb_quantizer);

        data_in = 0;
        shift = 0;

        passed = 0;
        failed = 0;
        seed = 12345;

        $display("========================================");
        $display(" GraphCore Quantizer Testbench");
        $display("========================================");

        // ====================================
        // TEST 1: All-zero inputs
        // ====================================

        $display("\nTEST 1: Zero inputs");

        data_in = 0;
        shift = 0;

        check_vector;

        // ====================================
        // TEST 2: No scaling
        // ====================================

        $display("\nTEST 2: No scaling");

        shift = 0;

        data_in[31:0]    =  32'sd10;
        data_in[63:32]   = -32'sd10;
        data_in[95:64]   =  32'sd50;
        data_in[127:96]  = -32'sd50;
        data_in[159:128] =  32'sd100;
        data_in[191:160] = -32'sd100;
        data_in[223:192] =  32'sd127;
        data_in[255:224] = -32'sd128;

        check_vector;

        // ====================================
        // TEST 3: Positive saturation
        // ====================================

        $display("\nTEST 3: Positive saturation");

        shift = 0;

        for (i = 0; i < FEATURE_DIM; i = i + 1)
            data_in[i*ACC_WIDTH +: ACC_WIDTH] =
                128 + i * 100;

        check_vector;

        // ====================================
        // TEST 4: Negative saturation
        // ====================================

        $display("\nTEST 4: Negative saturation");

        shift = 0;

        for (i = 0; i < FEATURE_DIM; i = i + 1)
            data_in[i*ACC_WIDTH +: ACC_WIDTH] =
                -129 - i * 100;

        check_vector;

        // ====================================
        // TEST 5: Arithmetic scaling
        // ====================================

        $display("\nTEST 5: Arithmetic scaling");

        shift = 4;

        data_in[31:0]    =  32'sd64;
        data_in[63:32]   =  32'sd160;
        data_in[95:64]   =  32'sd1600;
        data_in[127:96]  =  32'sd2032;
        data_in[159:128] =  32'sd2048;
        data_in[191:160] = -32'sd160;
        data_in[223:192] = -32'sd4096;
        data_in[255:224] =  32'sd8192;

        check_vector;

        // ====================================
        // TEST 6: Saturation boundaries
        // ====================================

        $display("\nTEST 6: Saturation boundaries");

        shift = 0;

        data_in[31:0]    =  32'sd126;
        data_in[63:32]   =  32'sd127;
        data_in[95:64]   =  32'sd128;
        data_in[127:96]  =  32'sd129;
        data_in[159:128] = -32'sd127;
        data_in[191:160] = -32'sd128;
        data_in[223:192] = -32'sd129;
        data_in[255:224] = -32'sd130;

        check_vector;

        // ====================================
        // TEST 7: Scaled saturation boundaries
        // ====================================

        $display("\nTEST 7: Scaled boundaries");

        shift = 4;

        data_in[31:0]    =  32'sd2031;
        data_in[63:32]   =  32'sd2032;
        data_in[95:64]   =  32'sd2047;
        data_in[127:96]  =  32'sd2048;
        data_in[159:128] = -32'sd2032;
        data_in[191:160] = -32'sd2047;
        data_in[223:192] = -32'sd2048;
        data_in[255:224] = -32'sd2049;

        check_vector;

        // ====================================
        // TEST 8: Negative shift behavior
        // ====================================

        $display("\nTEST 8: Negative floor division");

        shift = 1;

        data_in[31:0]    = -32'sd1;
        data_in[63:32]   = -32'sd3;
        data_in[95:64]   = -32'sd5;
        data_in[127:96]  = -32'sd7;
        data_in[159:128] =  32'sd1;
        data_in[191:160] =  32'sd3;
        data_in[223:192] =  32'sd5;
        data_in[255:224] =  32'sd7;

        check_vector;

        // ====================================
        // TEST 9: Signed INT32 boundaries
        // ====================================

        $display("\nTEST 9: INT32 boundaries");

        data_in[31:0]    = 32'h80000000;
        data_in[63:32]   = 32'h7FFFFFFF;
        data_in[95:64]   = 32'hFFFFFFFF;
        data_in[127:96]  = 32'h00000001;
        data_in[159:128] = 32'h00000000;
        data_in[191:160] = 32'h80000001;
        data_in[223:192] = 32'h7FFFFFFE;
        data_in[255:224] = 32'hFFFFFFFE;

        shift = 0;
        check_vector;

        shift = 4;
        check_vector;

        shift = 16;
        check_vector;

        shift = 31;
        check_vector;

        // ====================================
        // TEST 10: Every shift amount
        // ====================================

        $display("\nTEST 10: All shift amounts");

        data_in[31:0]    =  32'sd65536;
        data_in[63:32]   = -32'sd65536;
        data_in[95:64]   =  32'sd12345;
        data_in[127:96]  = -32'sd12345;
        data_in[159:128] =  32'h7FFFFFFF;
        data_in[191:160] =  32'h80000000;
        data_in[223:192] =  32'sd1;
        data_in[255:224] = -32'sd1;

        for (s = 0; s < 32; s = s + 1) begin

            shift = s;

            check_vector;

        end

        // ====================================
        // TEST 11: Independent lanes
        // ====================================

        $display("\nTEST 11: Independent lanes");

        shift = 2;

        for (i = 0; i < FEATURE_DIM; i = i + 1) begin

            data_in = 0;

            data_in[i*ACC_WIDTH +: ACC_WIDTH] =
                32'sd400;

            check_vector;

        end

        // ====================================
        // TEST 12: ReLU-compatible inputs
        // ====================================

        $display("\nTEST 12: ReLU-compatible inputs");

        shift = 4;

        for (i = 0; i < FEATURE_DIM; i = i + 1)
            data_in[i*ACC_WIDTH +: ACC_WIDTH] =
                i * 512;

        check_vector;

        // ====================================
        // TEST 13: Randomized full-width inputs
        // ====================================

        $display("\nTEST 13: Randomized inputs");

        for (i = 0; i < 100; i = i + 1) begin

            shift = $random(seed);

            for (j = 0; j < FEATURE_DIM; j = j + 1)
                data_in[j*ACC_WIDTH +: ACC_WIDTH] =
                    $random(seed);

            check_vector;

        end

        // ====================================
        // TEST 14: Randomized small inputs
        // ====================================

        $display("\nTEST 14: Small randomized inputs");

        for (i = 0; i < 100; i = i + 1) begin

            shift = $random(seed) & 5'h07;

            for (j = 0; j < FEATURE_DIM; j = j + 1)
                data_in[j*ACC_WIDTH +: ACC_WIDTH] =
                    $random(seed) % 4096;

            check_vector;

        end

        // ====================================
        // Final summary
        // ====================================

        $display("\n========================================");
        $display(" Test Results");
        $display("========================================");
        $display(" PASSED: %0d", passed);
        $display(" FAILED: %0d", failed);
        $display("========================================");

        if (failed == 0)
            $display("ALL QUANTIZER TESTS PASSED");
        else
            $fatal(1, "QUANTIZER VERIFICATION FAILED");

        $finish;

    end

    // Global simulation timeout
    initial begin
        #100000;
        $fatal(1, "SIMULATION TIMEOUT");
    end

endmodule
