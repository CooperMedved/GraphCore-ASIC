
`timescale 1ns/1ps

module tb_feature_memory;

    parameter MAX_NODES  = 64;
    parameter NODE_WIDTH = 6;
    parameter FEATURE_DIM = 8;
    parameter DATA_WIDTH = 8;

    localparam VECTOR_WIDTH = FEATURE_DIM * DATA_WIDTH;

    reg clk;
    reg we;

    reg [NODE_WIDTH-1:0] wr_addr;
    reg [VECTOR_WIDTH-1:0] wr_data;

    reg [NODE_WIDTH-1:0] rd_addr;
    wire [VECTOR_WIDTH-1:0] rd_data;

    integer passed;
    integer failed;
    integer i;
    integer j;

    reg [VECTOR_WIDTH-1:0] test_vector;

    // Reference memory
    reg [VECTOR_WIDTH-1:0] expected_memory [0:MAX_NODES-1];

    // Device under test
    feature_memory #(
        .MAX_NODES(MAX_NODES),
        .NODE_WIDTH(NODE_WIDTH),
        .FEATURE_DIM(FEATURE_DIM),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk(clk),
        .we(we),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .rd_addr(rd_addr),
        .rd_data(rd_data)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // General assertion task
    task check;
        input condition;
        input [8*100-1:0] description;

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

    // Write a feature vector
    task write_feature;
        input [NODE_WIDTH-1:0] addr;
        input [VECTOR_WIDTH-1:0] data;

        begin
            @(negedge clk);

            we      = 1;
            wr_addr = addr;
            wr_data = data;

            @(posedge clk);
            #1;

            expected_memory[addr] = data;

            @(negedge clk);
            we = 0;
        end
    endtask

    // Read and verify a feature vector
    task check_feature;
        input [NODE_WIDTH-1:0] addr;
        input [VECTOR_WIDTH-1:0] expected;

        begin
            rd_addr = addr;
            #1;

            if (rd_data === expected) begin

                $display(
                    "[PASS] NODE[%0d] = %h",
                    addr, rd_data
                );

                passed = passed + 1;

            end else begin

                $display(
                    "[FAIL] NODE[%0d] = %h Expected = %h",
                    addr, rd_data, expected
                );

                failed = failed + 1;

            end
        end
    endtask

    // Main test sequence
    initial begin

        $dumpfile("feature_memory_wave.vcd");
        $dumpvars(0, tb_feature_memory);

        we      = 0;
        wr_addr = 0;
        wr_data = 0;
        rd_addr = 0;

        passed = 0;
        failed = 0;

        $display("========================================");
        $display(" GraphCore Feature Memory Testbench");
        $display("========================================");

        // ====================================
        // TEST 1: Basic feature storage
        // ====================================

        $display("\nTEST 1: Basic feature storage");

        write_feature(0, 64'h0807060504030201);
        write_feature(1, 64'h1011121314151617);
        write_feature(2, 64'h0102030405060708);

        check_feature(0, 64'h0807060504030201);
        check_feature(1, 64'h1011121314151617);
        check_feature(2, 64'h0102030405060708);

        // ====================================
        // TEST 2: Feature packing
        // ====================================

        $display("\nTEST 2: Feature packing");

        rd_addr = 0;
        #1;

        for (i = 0; i < FEATURE_DIM; i = i + 1) begin

            check(
                rd_data[i*DATA_WIDTH +: DATA_WIDTH] == i+1,
                "Correct feature byte position"
            );

        end

        // ====================================
        // TEST 3: Signed INT8 features
        // ====================================

        $display("\nTEST 3: Signed INT8 features");

        // F0 = -1
        // F1 = -2
        // F2 = -3
        // F3 = -4
        // F4 =  4
        // F5 =  3
        // F6 =  2
        // F7 =  1

        write_feature(3, 64'h01020304FCFDFEFF);

        rd_addr = 3;
        #1;

        check($signed(rd_data[7:0]) == -1,
              "Feature 0 = -1");

        check($signed(rd_data[15:8]) == -2,
              "Feature 1 = -2");

        check($signed(rd_data[23:16]) == -3,
              "Feature 2 = -3");

        check($signed(rd_data[31:24]) == -4,
              "Feature 3 = -4");

        check($signed(rd_data[39:32]) == 4,
              "Feature 4 = 4");

        check($signed(rd_data[47:40]) == 3,
              "Feature 5 = 3");

        check($signed(rd_data[55:48]) == 2,
              "Feature 6 = 2");

        check($signed(rd_data[63:56]) == 1,
              "Feature 7 = 1");

        // ====================================
        // TEST 4: Signed INT8 boundaries
        // ====================================

        $display("\nTEST 4: Signed INT8 boundaries");

        write_feature(4, 64'h807F807F807F807F);

        rd_addr = 4;
        #1;

        for (i = 0; i < FEATURE_DIM; i = i + 1) begin

            if (i % 2 == 0) begin

                check(
                    $signed(rd_data[i*DATA_WIDTH +: DATA_WIDTH])
                    == 127,
                    "Maximum signed INT8 value"
                );

            end else begin

                check(
                    $signed(rd_data[i*DATA_WIDTH +: DATA_WIDTH])
                    == -128,
                    "Minimum signed INT8 value"
                );

            end

        end

        // ====================================
        // TEST 5: All-zero and all-one vectors
        // ====================================

        $display("\nTEST 5: Zero and one patterns");

        write_feature(5, 64'h0000000000000000);
        write_feature(6, 64'hFFFFFFFFFFFFFFFF);

        check_feature(5, 64'h0000000000000000);
        check_feature(6, 64'hFFFFFFFFFFFFFFFF);

        // ====================================
        // TEST 6: Write enable protection
        // ====================================

        $display("\nTEST 6: Write enable protection");

        write_feature(10, 64'h123456789ABCDEF0);

        @(negedge clk);

        we      = 0;
        wr_addr = 10;
        wr_data = 64'hFFFFFFFFFFFFFFFF;

        repeat (3) @(posedge clk);
        #1;

        check_feature(10, 64'h123456789ABCDEF0);

        // ====================================
        // TEST 7: Maximum node address
        // ====================================

        $display("\nTEST 7: Maximum node address");

        write_feature(63, 64'hAABBCCDDEEFF1122);

        check_feature(63, 64'hAABBCCDDEEFF1122);

        // ====================================
        // TEST 8: Overwrite existing features
        // ====================================

        $display("\nTEST 8: Overwrite feature vector");

        write_feature(10, 64'h1122334455667788);

        check_feature(10, 64'h1122334455667788);

        // ====================================
        // TEST 9: Synchronous write timing
        // ====================================

        $display("\nTEST 9: Synchronous write");

        write_feature(20, 64'hAAAAAAAAAAAAAAAA);

        @(negedge clk);

        rd_addr = 20;
        wr_addr = 20;
        wr_data = 64'hBBBBBBBBBBBBBBBB;
        we = 1;

        #1;

        check(
            rd_data === 64'hAAAAAAAAAAAAAAAA,
            "Old data retained before rising edge"
        );

        @(posedge clk);
        #1;

        check(
            rd_data === 64'hBBBBBBBBBBBBBBBB,
            "New data stored after rising edge"
        );

        expected_memory[20] = 64'hBBBBBBBBBBBBBBBB;

        @(negedge clk);
        we = 0;

        // ====================================
        // TEST 10: Asynchronous read timing
        // ====================================

        $display("\nTEST 10: Asynchronous read");

        @(negedge clk);

        rd_addr = 0;
        #1;

        check(
            rd_data === 64'h0807060504030201,
            "Read node 0 without clock edge"
        );

        rd_addr = 1;
        #1;

        check(
            rd_data === 64'h1011121314151617,
            "Read node 1 without clock edge"
        );

        rd_addr = 2;
        #1;

        check(
            rd_data === 64'h0102030405060708,
            "Read node 2 without clock edge"
        );

        // ====================================
        // TEST 11: Independent read and write
        // ====================================

        $display("\nTEST 11: Independent read and write");

        @(negedge clk);

        rd_addr = 0;

        we      = 1;
        wr_addr = 30;
        wr_data = 64'hDEADBEEF12345678;

        @(posedge clk);
        #1;

        check(
            rd_data === 64'h0807060504030201,
            "Read unaffected by write to another node"
        );

        expected_memory[30] = 64'hDEADBEEF12345678;

        @(negedge clk);
        we = 0;

        check_feature(30, 64'hDEADBEEF12345678);

        // ====================================
        // TEST 12: Full memory capacity
        // ====================================

        $display("\nTEST 12: Full memory capacity");

        for (i = 0; i < MAX_NODES; i = i + 1) begin

            for (j = 0; j < FEATURE_DIM; j = j + 1) begin

                test_vector[j*DATA_WIDTH +: DATA_WIDTH]
                    = (i * 13) + (j * 7);

            end

            write_feature(i, test_vector);

        end

        for (i = 0; i < MAX_NODES; i = i + 1) begin

            check_feature(i, expected_memory[i]);

        end

        // ====================================
        // TEST 13: Data retention
        // ====================================

        $display("\nTEST 13: Data retention");

        we = 0;

        repeat (20) @(posedge clk);
        #1;

        for (i = 0; i < MAX_NODES; i = i + 1) begin

            check_feature(i, expected_memory[i]);

        end

        // Final summary

        $display("\n========================================");
        $display(" Test Results");
        $display("========================================");
        $display(" PASSED: %0d", passed);
        $display(" FAILED: %0d", failed);
        $display("========================================");

        if (failed == 0)
            $display("ALL FEATURE MEMORY TESTS PASSED");
        else
            $fatal(1, "FEATURE MEMORY VERIFICATION FAILED");

        $finish;

    end

    // Global simulation timeout
    initial begin
        #100000;
        $fatal(1, "SIMULATION TIMEOUT");
    end

endmodule
