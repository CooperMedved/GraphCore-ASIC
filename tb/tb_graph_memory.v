
`timescale 1ns/1ps

module tb_graph_memory;

    parameter MAX_NODES  = 64;
    parameter MAX_EDGES  = 256;
    parameter NODE_WIDTH = 6;
    parameter EDGE_WIDTH = 9;

    reg clk;

    // Row pointer write interface
    reg row_we;
    reg [NODE_WIDTH:0] row_wr_addr;
    reg [EDGE_WIDTH-1:0] row_wr_data;

    // Column index write interface
    reg col_we;
    reg [EDGE_WIDTH-1:0] col_wr_addr;
    reg [NODE_WIDTH-1:0] col_wr_data;

    // Read interfaces
    reg [NODE_WIDTH:0] row_addr;
    wire [EDGE_WIDTH-1:0] row_data;

    reg [EDGE_WIDTH-1:0] col_addr;
    wire [NODE_WIDTH-1:0] col_data;

    integer passed;
    integer failed;
    integer i;

    // Device under test
    graph_memory #(
        .MAX_NODES(MAX_NODES),
        .MAX_EDGES(MAX_EDGES),
        .NODE_WIDTH(NODE_WIDTH),
        .EDGE_WIDTH(EDGE_WIDTH)
    ) dut (
        .clk(clk),

        .row_we(row_we),
        .row_wr_addr(row_wr_addr),
        .row_wr_data(row_wr_data),

        .col_we(col_we),
        .col_wr_addr(col_wr_addr),
        .col_wr_data(col_wr_data),

        .row_addr(row_addr),
        .row_data(row_data),

        .col_addr(col_addr),
        .col_data(col_data)
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

    // Write row pointer memory
    task write_row;
        input [NODE_WIDTH:0] addr;
        input [EDGE_WIDTH-1:0] data;

        begin
            @(negedge clk);

            row_we      = 1;
            row_wr_addr = addr;
            row_wr_data = data;
            col_we      = 0;

            @(posedge clk);
            #1;

            @(negedge clk);
            row_we = 0;
        end
    endtask

    // Write column index memory
    task write_col;
        input [EDGE_WIDTH-1:0] addr;
        input [NODE_WIDTH-1:0] data;

        begin
            @(negedge clk);

            col_we      = 1;
            col_wr_addr = addr;
            col_wr_data = data;
            row_we      = 0;

            @(posedge clk);
            #1;

            @(negedge clk);
            col_we = 0;
        end
    endtask

    // Read and verify row pointer
    task check_row;
        input [NODE_WIDTH:0] addr;
        input [EDGE_WIDTH-1:0] expected;

        begin
            row_addr = addr;
            #1;

            if (row_data !== expected) begin
                $display(
                    "[FAIL] ROW[%0d] = %0d Expected = %0d",
                    addr, row_data, expected
                );

                failed = failed + 1;
            end else begin
                $display(
                    "[PASS] ROW[%0d] = %0d",
                    addr, row_data
                );

                passed = passed + 1;
            end
        end
    endtask

    // Read and verify column index
    task check_col;
        input [EDGE_WIDTH-1:0] addr;
        input [NODE_WIDTH-1:0] expected;

        begin
            col_addr = addr;
            #1;

            if (col_data !== expected) begin
                $display(
                    "[FAIL] COL[%0d] = %0d Expected = %0d",
                    addr, col_data, expected
                );

                failed = failed + 1;
            end else begin
                $display(
                    "[PASS] COL[%0d] = %0d",
                    addr, col_data
                );

                passed = passed + 1;
            end
        end
    endtask

    // Main test sequence
    initial begin

        $dumpfile("graph_memory_wave.vcd");
        $dumpvars(0, tb_graph_memory);

        row_we      = 0;
        row_wr_addr = 0;
        row_wr_data = 0;

        col_we      = 0;
        col_wr_addr = 0;
        col_wr_data = 0;

        row_addr = 0;
        col_addr = 0;

        passed = 0;
        failed = 0;

        $display("========================================");
        $display(" GraphCore Graph Memory Testbench");
        $display("========================================");

        // ====================================
        // TEST 1: Load CSR row pointers
        // ====================================

        $display("\nTEST 1: Row pointer memory");

        write_row(0, 0);
        write_row(1, 2);
        write_row(2, 4);
        write_row(3, 7);
        write_row(4, 8);

        check_row(0, 0);
        check_row(1, 2);
        check_row(2, 4);
        check_row(3, 7);
        check_row(4, 8);

        // ====================================
        // TEST 2: Load CSR column indices
        // ====================================

        $display("\nTEST 2: Column index memory");

        write_col(0, 1);
        write_col(1, 2);
        write_col(2, 0);
        write_col(3, 2);
        write_col(4, 0);
        write_col(5, 1);
        write_col(6, 3);
        write_col(7, 2);

        check_col(0, 1);
        check_col(1, 2);
        check_col(2, 0);
        check_col(3, 2);
        check_col(4, 0);
        check_col(5, 1);
        check_col(6, 3);
        check_col(7, 2);

        // ====================================
        // TEST 3: Simultaneous writes
        // ====================================

        $display("\nTEST 3: Simultaneous writes");

        @(negedge clk);

        row_we      = 1;
        row_wr_addr = 10;
        row_wr_data = 100;

        col_we      = 1;
        col_wr_addr = 10;
        col_wr_data = 25;

        @(posedge clk);
        #1;

        @(negedge clk);

        row_we = 0;
        col_we = 0;

        check_row(10, 100);
        check_col(10, 25);

        // ====================================
        // TEST 4: Write enable protection
        // ====================================

        $display("\nTEST 4: Write enable protection");

        @(negedge clk);

        row_we      = 0;
        row_wr_addr = 10;
        row_wr_data = 200;

        col_we      = 0;
        col_wr_addr = 10;
        col_wr_data = 50;

        repeat (3) @(posedge clk);
        #1;

        check_row(10, 100);
        check_col(10, 25);

        // ====================================
        // TEST 5: Maximum valid addresses
        // ====================================

        $display("\nTEST 5: Maximum valid addresses");

        write_row(64, 256);
        write_col(255, 63);

        check_row(64, 256);
        check_col(255, 63);

        // ====================================
        // TEST 6: Invalid read addresses
        // ====================================

        $display("\nTEST 6: Invalid read addresses");

        check_row(65, 0);
        check_row(127, 0);

        check_col(256, 0);
        check_col(511, 0);

        // ====================================
        // TEST 7: Invalid write addresses
        // ====================================

        $display("\nTEST 7: Invalid write addresses");

        write_row(65, 511);
        write_row(127, 511);

        write_col(256, 63);
        write_col(511, 63);

        // Verify valid boundary locations
        // were not corrupted.

        check_row(64, 256);
        check_col(255, 63);

        check_row(0, 0);
        check_col(0, 1);

        check_row(65, 0);
        check_col(256, 0);

        // ====================================
        // TEST 8: Synchronous write timing
        // ====================================

        $display("\nTEST 8: Synchronous write timing");

        write_row(20, 50);

        @(negedge clk);

        row_addr    = 20;
        row_we      = 1;
        row_wr_addr = 20;
        row_wr_data = 150;

        #1;

        check(row_data === 9'd50,
              "Old data retained before rising edge");

        @(posedge clk);
        #1;

        check(row_data === 9'd150,
              "New data stored after rising edge");

        @(negedge clk);
        row_we = 0;

        // ====================================
        // TEST 9: Asynchronous read timing
        // ====================================

        $display("\nTEST 9: Asynchronous reads");

        @(negedge clk);

        row_addr = 1;
        col_addr = 0;
        #1;

        check(row_data === 9'd2,
              "Row asynchronous read");

        check(col_data === 6'd1,
              "Column asynchronous read");

        // Change addresses without clock edge
        row_addr = 3;
        col_addr = 1;
        #1;

        check(row_data === 9'd7,
              "Row data updates without clock");

        check(col_data === 6'd2,
              "Column data updates without clock");

        // ====================================
        // TEST 10: Full row memory capacity
        // ====================================

        $display("\nTEST 10: Full row memory");

        for (i = 0; i <= MAX_NODES; i = i + 1)
            write_row(i, i * 4);

        for (i = 0; i <= MAX_NODES; i = i + 1)
            check_row(i, i * 4);

        // ====================================
        // TEST 11: Full column memory capacity
        // ====================================

        $display("\nTEST 11: Full column memory");

        for (i = 0; i < MAX_EDGES; i = i + 1)
            write_col(i, i % MAX_NODES);

        for (i = 0; i < MAX_EDGES; i = i + 1)
            check_col(i, i % MAX_NODES);

        // ====================================
        // TEST 12: Data retention
        // ====================================

        $display("\nTEST 12: Data retention");

        row_we = 0;
        col_we = 0;

        repeat (20) @(posedge clk);
        #1;

        check_row(0, 0);
        check_row(32, 128);
        check_row(64, 256);

        check_col(0, 0);
        check_col(127, 63);
        check_col(255, 63);

        // Final summary

        $display("\n========================================");
        $display(" Test Results");
        $display("========================================");
        $display(" PASSED: %0d", passed);
        $display(" FAILED: %0d", failed);
        $display("========================================");

        if (failed == 0)
            $display("ALL GRAPH MEMORY TESTS PASSED");
        else
            $fatal(1, "GRAPH MEMORY VERIFICATION FAILED");

        $finish;

    end

    // Simulation timeout
    initial begin
        #100000;
        $fatal(1, "SIMULATION TIMEOUT");
    end

endmodule
