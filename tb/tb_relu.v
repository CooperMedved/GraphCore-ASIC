
`timescale 1ns/1ps

module tb_relu;

    parameter FEATURE_DIM = 8;
    parameter ACC_WIDTH = 32;

    localparam VECTOR_WIDTH = FEATURE_DIM * ACC_WIDTH;

    reg [VECTOR_WIDTH-1:0] data_in;
    wire [VECTOR_WIDTH-1:0] data_out;

    integer passed;
    integer failed;
    integer i;
    integer j;
    integer seed;

    reg signed [ACC_WIDTH-1:0] input_value;
    reg signed [ACC_WIDTH-1:0] expected_value;
    reg signed [ACC_WIDTH-1:0] actual_value;

    // Device under test
    relu #(
        .FEATURE_DIM(FEATURE_DIM),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .data_in(data_in),
        .data_out(data_out)
    );

    // Reference model and assertion task
    task check_vector;
        integer k;

        begin

            // Allow combinational logic to settle
            #1;

            for (k = 0; k < FEATURE_DIM; k = k + 1) begin

                input_value =
                    $signed(data_in[k*ACC_WIDTH +: ACC_WIDTH]);

                actual_value =
                    $signed(data_out[k*ACC_WIDTH +: ACC_WIDTH]);

                // Software reference model
                if (input_value < 0)
                    expected_value = 0;
                else
                    expected_value = input_value;

                if (actual_value === expected_value) begin

                    $display(
                        "[PASS] Lane %0d: Input=%0d Output=%0d",
                        k, input_value, actual_value
                    );

                    passed = passed + 1;

                end else begin

                    $display(
                        "[FAIL] Lane %0d: Input=%0d Output=%0d Expected=%0d",
                        k, input_value, actual_value, expected_value
                    );

                    failed = failed + 1;

                end
            end
        end
    endtask

    // Main test sequence
    initial begin

        $dumpfile("relu_wave.vcd");
        $dumpvars(0, tb_relu);

        data_in = 0;
        passed = 0;
        failed = 0;
        seed = 12345;

        $display("========================================");
        $display(" GraphCore ReLU Testbench");
        $display("========================================");

        // ====================================
        // TEST 1: All-zero inputs
        // ====================================

        $display("\nTEST 1: All-zero inputs");

        data_in = 0;

        check_vector;

        // ====================================
        // TEST 2: All-positive inputs
        // ====================================

        $display("\nTEST 2: Positive inputs");

        for (i = 0; i < FEATURE_DIM; i = i + 1)
            data_in[i*ACC_WIDTH +: ACC_WIDTH] =
                (i + 1) * 10;

        check_vector;

        // ====================================
        // TEST 3: All-negative inputs
        // ====================================

        $display("\nTEST 3: Negative inputs");

        for (i = 0; i < FEATURE_DIM; i = i + 1)
            data_in[i*ACC_WIDTH +: ACC_WIDTH] =
                -(i + 1) * 10;

        check_vector;

        // ====================================
        // TEST 4: Mixed feature vector
        // ====================================

        $display("\nTEST 4: Mixed inputs");

        data_in[31:0]    = -32'sd45;
        data_in[63:32]   =  32'sd23;
        data_in[95:64]   = -32'sd12;
        data_in[127:96]  =  32'sd0;
        data_in[159:128] =  32'sd150;
        data_in[191:160] = -32'sd90;
        data_in[223:192] =  32'sd64;
        data_in[255:224] =  32'sd8;

        check_vector;

        // ====================================
        // TEST 5: Signed INT32 boundaries
        // ====================================

        $display("\nTEST 5: INT32 boundaries");

        data_in[31:0]    = 32'h80000000;
        data_in[63:32]   = 32'h7FFFFFFF;
        data_in[95:64]   = 32'hFFFFFFFF;
        data_in[127:96]  = 32'h00000001;
        data_in[159:128] = 32'h00000000;
        data_in[191:160] = 32'h80000001;
        data_in[223:192] = 32'h7FFFFFFE;
        data_in[255:224] = 32'hFFFFFFFE;

        check_vector;

        // ====================================
        // TEST 6: Maximum positive values
        // ====================================

        $display("\nTEST 6: Maximum positive values");

        for (i = 0; i < FEATURE_DIM; i = i + 1)
            data_in[i*ACC_WIDTH +: ACC_WIDTH] =
                32'h7FFFFFFF;

        check_vector;

        // ====================================
        // TEST 7: Minimum negative values
        // ====================================

        $display("\nTEST 7: Minimum negative values");

        for (i = 0; i < FEATURE_DIM; i = i + 1)
            data_in[i*ACC_WIDTH +: ACC_WIDTH] =
                32'h80000000;

        check_vector;

        // ====================================
        // TEST 8: Independent lane operation
        // ====================================

        $display("\nTEST 8: Independent lanes");

        for (i = 0; i < FEATURE_DIM; i = i + 1) begin

            // Set every lane to -1
            data_in = {VECTOR_WIDTH{1'b1}};

            // Only one lane is positive
            data_in[i*ACC_WIDTH +: ACC_WIDTH] =
                32'sd1234;

            check_vector;

        end

        // ====================================
        // TEST 9: Sign-bit transitions
        // ====================================

        $display("\nTEST 9: Sign-bit transitions");

        for (i = 0; i < FEATURE_DIM; i = i + 1)
            data_in[i*ACC_WIDTH +: ACC_WIDTH] =
                32'hFFFFFFFF;

        check_vector;

        data_in = 0;

        check_vector;

        for (i = 0; i < FEATURE_DIM; i = i + 1)
            data_in[i*ACC_WIDTH +: ACC_WIDTH] =
                32'sd1;

        check_vector;

        // ====================================
        // TEST 10: Randomized verification
        // ====================================

        $display("\nTEST 10: Randomized inputs");

        for (i = 0; i < 100; i = i + 1) begin

            for (j = 0; j < FEATURE_DIM; j = j + 1)
                data_in[j*ACC_WIDTH +: ACC_WIDTH] =
                    $random(seed);

            check_vector;

        end

        // ====================================
        // TEST 11: Walking-one bit patterns
        // ====================================

        $display("\nTEST 11: Walking-one patterns");

        for (i = 0; i < ACC_WIDTH; i = i + 1) begin

            for (j = 0; j < FEATURE_DIM; j = j + 1)
                data_in[j*ACC_WIDTH +: ACC_WIDTH] =
                    32'h00000001 << i;

            check_vector;

        end

        // Final summary
        $display("\n========================================");
        $display(" Test Results");
        $display("========================================");
        $display(" PASSED: %0d", passed);
        $display(" FAILED: %0d", failed);
        $display("========================================");

        if (failed == 0)
            $display("ALL RELU TESTS PASSED");
        else
            $fatal(1, "RELU VERIFICATION FAILED");

        $finish;

    end

    // Global simulation timeout
    initial begin
        #100000;
        $fatal(1, "SIMULATION TIMEOUT");
    end

endmodule
