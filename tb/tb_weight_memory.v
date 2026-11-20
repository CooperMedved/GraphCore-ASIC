
`timescale 1ns/1ps

module tb_weight_memory;

    parameter INPUT_DIM  = 16;
    parameter OUTPUT_DIM = 8;
    parameter ARRAY_SIZE = 4;
    parameter DATA_WIDTH = 8;
    parameter ADDR_WIDTH = 5;

    localparam NUM_TILES = OUTPUT_DIM / ARRAY_SIZE;
    localparam MEM_DEPTH = INPUT_DIM * NUM_TILES;
    localparam WORD_WIDTH = ARRAY_SIZE * DATA_WIDTH;

    reg clk;
    reg we;

    reg [ADDR_WIDTH-1:0] wr_addr;
    reg [WORD_WIDTH-1:0] wr_data;

    reg [ADDR_WIDTH-1:0] rd_addr;
    wire [WORD_WIDTH-1:0] rd_data;

    integer passed;
    integer failed;
    integer i;
    integer j;
    integer k;
    integer tile;

    reg [WORD_WIDTH-1:0] test_word;

    // Reference memory
    reg [WORD_WIDTH-1:0] expected_memory [0:MEM_DEPTH-1];

    // Device under test
    weight_memory #(
        .INPUT_DIM(INPUT_DIM),
        .OUTPUT_DIM(OUTPUT_DIM),
        .ARRAY_SIZE(ARRAY_SIZE),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
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

    // Write weight word
    task write_weight;
        input [ADDR_WIDTH-1:0] addr;
        input [WORD_WIDTH-1:0] data;

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

    // Read and verify weight word
    task check_weight;
        input [ADDR_WIDTH-1:0] addr;
        input [WORD_WIDTH-1:0] expected;

        begin
            rd_addr = addr;
            #1;

            if (rd_data === expected) begin

                $display(
                    "[PASS] WEIGHT[%0d] = %h",
                    addr, rd_data
                );

                passed = passed + 1;

            end else begin

                $display(
                    "[FAIL] WEIGHT[%0d] = %h Expected = %h",
                    addr, rd_data, expected
                );

                failed = failed + 1;
            end
        end
    endtask

    // Main test sequence
    initial begin

        $dumpfile("weight_memory_wave.vcd");
        $dumpvars(0, tb_weight_memory);

        we      = 0;
        wr_addr = 0;
        wr_data = 0;
        rd_addr = 0;

        passed = 0;
        failed = 0;

        $display("========================================");
        $display(" GraphCore Weight Memory Testbench");
        $display("========================================");

        // ====================================
        // TEST 1: Basic storage
        // ====================================

        $display("\nTEST 1: Basic storage");

        write_weight(0, 32'h04030201);
        write_weight(1, 32'h08070605);
        write_weight(2, 32'h0C0B0A09);

        check_weight(0, 32'h04030201);
        check_weight(1, 32'h08070605);
        check_weight(2, 32'h0C0B0A09);

        // ====================================
        // TEST 2: Weight packing
        // ====================================

        $display("\nTEST 2: Weight packing");

        rd_addr = 0;
        #1;

        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin

            check(
                rd_data[i*DATA_WIDTH +: DATA_WIDTH]
                == i+1,
                "Correct weight byte position"
            );

        end

        // ====================================
        // TEST 3: Signed INT8 weights
        // ====================================

        $display("\nTEST 3: Signed weights");

        // W0 = -1
        // W1 = -2
        // W2 =  3
        // W3 =  4

        write_weight(3, 32'h0403FEFF);

        rd_addr = 3;
        #1;

        check($signed(rd_data[7:0]) == -1,
              "Weight 0 = -1");

        check($signed(rd_data[15:8]) == -2,
              "Weight 1 = -2");

        check($signed(rd_data[23:16]) == 3,
              "Weight 2 = 3");

        check($signed(rd_data[31:24]) == 4,
              "Weight 3 = 4");

        // ====================================
        // TEST 4: Signed INT8 boundaries
        // ====================================

        $display("\nTEST 4: INT8 boundaries");

        write_weight(4, 32'h807F807F);

        rd_addr = 4;
        #1;

        check($signed(rd_data[7:0]) == 127,
              "Maximum INT8");

        check($signed(rd_data[15:8]) == -128,
              "Minimum INT8");

        check($signed(rd_data[23:16]) == 127,
              "Maximum INT8");

        check($signed(rd_data[31:24]) == -128,
              "Minimum INT8");

        // ====================================
        // TEST 5: Zero and one patterns
        // ====================================

        $display("\nTEST 5: Zero and one patterns");

        write_weight(5, 32'h00000000);
        write_weight(6, 32'hFFFFFFFF);

        check_weight(5, 32'h00000000);
        check_weight(6, 32'hFFFFFFFF);

        // ====================================
        // TEST 6: Write enable protection
        // ====================================

        $display("\nTEST 6: Write enable protection");

        write_weight(10, 32'h12345678);

        @(negedge clk);

        we      = 0;
        wr_addr = 10;
        wr_data = 32'hFFFFFFFF;

        repeat (3) @(posedge clk);
        #1;

        check_weight(10, 32'h12345678);

        // ====================================
        // TEST 7: Maximum memory address
        // ====================================

        $display("\nTEST 7: Maximum address");

        write_weight(31, 32'hAABBCCDD);

        check_weight(31, 32'hAABBCCDD);

        // ====================================
        // TEST 8: Overwrite existing weights
        // ====================================

        $display("\nTEST 8: Overwriting weights");

        write_weight(10, 32'hDEADBEEF);

        check_weight(10, 32'hDEADBEEF);

        // ====================================
        // TEST 9: Synchronous write timing
        // ====================================

        $display("\nTEST 9: Synchronous write");

        write_weight(20, 32'hAAAAAAAA);

        @(negedge clk);

        rd_addr = 20;
        wr_addr = 20;
        wr_data = 32'hBBBBBBBB;
        we = 1;

        #1;

        check(
            rd_data === 32'hAAAAAAAA,
            "Old data retained before rising edge"
        );

        @(posedge clk);
        #1;

        check(
            rd_data === 32'hBBBBBBBB,
            "New data stored after rising edge"
        );

        expected_memory[20] = 32'hBBBBBBBB;

        @(negedge clk);
        we = 0;

        // ====================================
        // TEST 10: Asynchronous read
        // ====================================

        $display("\nTEST 10: Asynchronous reads");

        @(negedge clk);

        rd_addr = 0;
        #1;

        check(
            rd_data === 32'h04030201,
            "Read address 0"
        );

        rd_addr = 1;
        #1;

        check(
            rd_data === 32'h08070605,
            "Read address 1 without clock edge"
        );

        rd_addr = 2;
        #1;

        check(
            rd_data === 32'h0C0B0A09,
            "Read address 2 without clock edge"
        );

        // ====================================
        // TEST 11: Independent read and write
        // ====================================

        $display("\nTEST 11: Independent read and write");

        @(negedge clk);

        rd_addr = 0;

        we      = 1;
        wr_addr = 25;
        wr_data = 32'hCAFEBABE;

        @(posedge clk);
        #1;

        check(
            rd_data === 32'h04030201,
            "Independent read unaffected by write"
        );

        expected_memory[25] = 32'hCAFEBABE;

        @(negedge clk);
        we = 0;

        check_weight(25, 32'hCAFEBABE);

        // ====================================
        // TEST 12: Load complete weight matrix
        // ====================================

        $display("\nTEST 12: Full weight matrix");

        for (k = 0; k < INPUT_DIM; k = k + 1) begin

            for (tile = 0;
                 tile < NUM_TILES;
                 tile = tile + 1) begin

                for (j = 0;
                     j < ARRAY_SIZE;
                     j = j + 1) begin

                    test_word[j*DATA_WIDTH +: DATA_WIDTH]
                        = (k * OUTPUT_DIM)
                        + (tile * ARRAY_SIZE)
                        + j - 64;

                end

                write_weight(
                    k * NUM_TILES + tile,
                    test_word
                );

            end
        end

        // Verify all memory words

        for (i = 0; i < MEM_DEPTH; i = i + 1) begin

            check_weight(i, expected_memory[i]);

        end

        // ====================================
        // TEST 13: Weight tile addressing
        // ====================================

        $display("\nTEST 13: Tile addressing");

        for (k = 0; k < INPUT_DIM; k = k + 1) begin

            for (tile = 0;
                 tile < NUM_TILES;
                 tile = tile + 1) begin

                rd_addr = k * NUM_TILES + tile;

                #1;

                for (j = 0;
                     j < ARRAY_SIZE;
                     j = j + 1) begin

                    check(
                        $signed(
                            rd_data[
                                j*DATA_WIDTH +: DATA_WIDTH
                            ]
                        ) ==
                        ((k * OUTPUT_DIM)
                        + (tile * ARRAY_SIZE)
                        + j - 64),

                        "Correct matrix weight and tile"
                    );

                end

            end
        end

        // ====================================
        // TEST 14: Data retention
        // ====================================

        $display("\nTEST 14: Data retention");

        we = 0;

        repeat (20) @(posedge clk);
        #1;

        for (i = 0; i < MEM_DEPTH; i = i + 1) begin

            check_weight(i, expected_memory[i]);

        end

        // Final summary

        $display("\n========================================");
        $display(" Test Results");
        $display("========================================");
        $display(" PASSED: %0d", passed);
        $display(" FAILED: %0d", failed);
        $display("========================================");

        if (failed == 0)
            $display("ALL WEIGHT MEMORY TESTS PASSED");
        else
            $fatal(1, "WEIGHT MEMORY VERIFICATION FAILED");

        $finish;

    end

    // Global simulation timeout
    initial begin
        #100000;
        $fatal(1, "SIMULATION TIMEOUT");
    end

endmodule
