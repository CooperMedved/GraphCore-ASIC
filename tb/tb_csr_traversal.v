
`timescale 1ns/1ps

module tb_csr_traversal;

    parameter NODE_WIDTH = 6;
    parameter EDGE_WIDTH = 9;

    reg clk;
    reg rst;
    reg start;

    reg [NODE_WIDTH-1:0] target_node;

    wire [NODE_WIDTH:0] row_addr;
    wire [EDGE_WIDTH-1:0] row_data;

    wire [EDGE_WIDTH-1:0] col_addr;
    wire [NODE_WIDTH-1:0] col_data;

    wire [NODE_WIDTH-1:0] neighbor_id;
    wire neighbor_valid;
    reg neighbor_ready;

    wire busy;
    wire done;

    // Simulated CSR graph memories
    reg [EDGE_WIDTH-1:0] row_ptr [0:64];
    reg [NODE_WIDTH-1:0] col_idx [0:255];

    integer passed;
    integer failed;
    integer i;

    // Asynchronous memory reads
    assign row_data = row_ptr[row_addr];
    assign col_data = col_addr < 256 ?
                      col_idx[col_addr] : 0;

    // Device under test
    csr_traversal #(
        .NODE_WIDTH(NODE_WIDTH),
        .EDGE_WIDTH(EDGE_WIDTH)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .target_node(target_node),

        .row_addr(row_addr),
        .row_data(row_data),

        .col_addr(col_addr),
        .col_data(col_data),

        .neighbor_id(neighbor_id),
        .neighbor_valid(neighbor_valid),
        .neighbor_ready(neighbor_ready),

        .busy(busy),
        .done(done)
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

    // Reset DUT
    task reset_dut;
        begin
            @(negedge clk);

            rst = 1;
            start = 0;
            neighbor_ready = 0;

            @(posedge clk);
            #1;

            @(negedge clk);
            rst = 0;
        end
    endtask

    // Start traversal
    task start_traversal;
        input [NODE_WIDTH-1:0] node;

        begin
            @(negedge clk);

            target_node = node;
            start = 1;

            @(posedge clk);
            #1;

            check(busy === 1'b1,
                  "Busy asserted after start");

            @(negedge clk);
            start = 0;
        end
    endtask

    // Wait for completion
    task wait_done;
        integer timeout;

        begin
            timeout = 0;

            while (done !== 1'b1 &&
                   timeout < 300) begin

                @(posedge clk);
                #1;

                timeout = timeout + 1;
            end

            check(done === 1'b1,
                  "Traversal completed");

            check(busy === 1'b0,
                  "Busy deasserted");

            check(neighbor_valid === 1'b0,
                  "Neighbor valid deasserted");

            @(posedge clk);
            #1;

            check(done === 1'b0,
                  "Done is a one-cycle pulse");
        end
    endtask

    // Traverse node and check every neighbor
    task test_node;
        input [NODE_WIDTH-1:0] node;

        integer expected_index;
        integer end_index;
        integer timeout;
        integer received;

        begin
            expected_index = row_ptr[node];
            end_index = row_ptr[node + 1];
            received = 0;
            timeout = 0;

            @(negedge clk);
            neighbor_ready = 0;

            start_traversal(node);

            neighbor_ready = 1;

            while (done !== 1'b1 &&
                   timeout < 300) begin

                @(posedge clk);

                // Sample handshake before NBA updates
                if (neighbor_valid &&
                    neighbor_ready) begin

                    if (expected_index < end_index) begin

                        check(
                            neighbor_id ===
                            col_idx[expected_index],
                            "Correct neighbor ID"
                        );

                        check(
                            col_addr == expected_index,
                            "Correct column address"
                        );

                    end else begin

                        check(1'b0,
                              "Unexpected extra neighbor");

                    end

                    expected_index = expected_index + 1;
                    received = received + 1;
                end

                #1;
                timeout = timeout + 1;
            end

            check(done === 1'b1,
                  "Traversal completed");

            check(received ==
                  row_ptr[node + 1] - row_ptr[node],
                  "Correct number of neighbors");

            check(busy === 1'b0,
                  "Busy deasserted");

            check(neighbor_valid === 1'b0,
                  "Neighbor stream stopped");

            @(posedge clk);
            #1;

            check(done === 1'b0,
                  "Done pulse cleared");

            @(negedge clk);
            neighbor_ready = 0;
        end
    endtask

    // Main test sequence
    initial begin

        $dumpfile("csr_traversal_wave.vcd");
        $dumpvars(0, tb_csr_traversal);

        rst = 1;
        start = 0;
        target_node = 0;
        neighbor_ready = 0;

        passed = 0;
        failed = 0;

        // Initialize graph memories
        for (i = 0; i < 65; i = i + 1)
            row_ptr[i] = 8;

        for (i = 0; i < 256; i = i + 1)
            col_idx[i] = 0;

        // Example graph:
        // Node 0: 1, 2
        // Node 1: 0, 2
        // Node 2: 0, 1, 3
        // Node 3: 2
        // Node 4: isolated

        row_ptr[0] = 0;
        row_ptr[1] = 2;
        row_ptr[2] = 4;
        row_ptr[3] = 7;
        row_ptr[4] = 8;
        row_ptr[5] = 8;

        col_idx[0] = 1;
        col_idx[1] = 2;
        col_idx[2] = 0;
        col_idx[3] = 2;
        col_idx[4] = 0;
        col_idx[5] = 1;
        col_idx[6] = 3;
        col_idx[7] = 2;

        $display("========================================");
        $display(" GraphCore CSR Traversal Testbench");
        $display("========================================");

        // TEST 1: Reset

        $display("\nTEST 1: Reset");

        reset_dut;

        check(busy === 1'b0, "Busy reset");
        check(done === 1'b0, "Done reset");
        check(neighbor_valid === 1'b0,
              "Neighbor valid reset");
        check(row_addr === 0,
              "Row address reset");
        check(col_addr === 0,
              "Column address reset");

        // TEST 2: Multiple neighbors

        $display("\nTEST 2: Node 0");
        test_node(0);

        // TEST 3: Consecutive traversal

        $display("\nTEST 3: Node 1");
        test_node(1);

        // TEST 4: Three neighbors

        $display("\nTEST 4: Node 2");
        test_node(2);

        // TEST 5: Single neighbor

        $display("\nTEST 5: Node 3");
        test_node(3);

        // TEST 6: Isolated node

        $display("\nTEST 6: Isolated node");
        test_node(4);

        // TEST 7: Backpressure

        $display("\nTEST 7: Backpressure");

        start_traversal(2);

        neighbor_ready = 0;

        repeat (3) @(posedge clk);
        #1;

        check(neighbor_valid === 1'b1,
              "Neighbor valid during stall");

        check(col_addr === 9'd4,
              "First edge address");

        repeat (5) begin
            @(posedge clk);
            #1;

            check(col_addr === 9'd4,
                  "Edge address held during stall");

            check(neighbor_id === 6'd0,
                  "Neighbor ID held during stall");

            check(neighbor_valid === 1'b1,
                  "Valid remains asserted");
        end

        // Resume streaming

        @(negedge clk);
        neighbor_ready = 1;

        @(posedge clk);
        #1;

        check(col_addr === 9'd5,
              "Traversal resumes after stall");

        wait_done;

        // TEST 8: Target node changes while busy

        $display("\nTEST 8: Target node changes");

        @(negedge clk);
        neighbor_ready = 0;

        start_traversal(2);

        target_node = 63;

        repeat (3) @(posedge clk);
        #1;

        check(row_addr === 7'd3,
              "Original target node preserved");

        check(col_addr === 9'd4,
              "Original edge address preserved");

        @(negedge clk);
        neighbor_ready = 1;

        wait_done;

        // TEST 9: Maximum node and edge addresses

        $display("\nTEST 9: Maximum addresses");

        // Valid CSR layout ending at edge index 256
        for (i = 5; i < 63; i = i + 1)
            row_ptr[i] = 8;

        row_ptr[63] = 255;
        row_ptr[64] = 256;

        col_idx[255] = 42;

        test_node(63);

        check(row_addr === 7'd64,
              "Maximum row pointer address");

        check(col_addr === 9'd255,
              "Maximum valid edge address");

        // TEST 10: Full 256-edge traversal

        $display("\nTEST 10: Full edge capacity");

        row_ptr[0] = 0;

        for (i = 1; i < 65; i = i + 1)
            row_ptr[i] = 256;

        for (i = 0; i < 256; i = i + 1)
            col_idx[i] = i % 64;

        test_node(0);

        // TEST 11: Reset during traversal

        $display("\nTEST 11: Reset during traversal");

        start_traversal(0);

        neighbor_ready = 1;

        repeat (5) @(posedge clk);
        #1;

        check(busy === 1'b1,
              "Traversal active before reset");

        reset_dut;

        check(busy === 1'b0,
              "Reset cancels traversal");

        check(done === 1'b0,
              "Done cleared after reset");

        check(neighbor_valid === 1'b0,
              "Neighbor stream stopped by reset");

        check(col_addr === 0,
              "Edge counter reset");

        // Final summary

        $display("\n========================================");
        $display(" Test Results");
        $display("========================================");
        $display(" PASSED: %0d", passed);
        $display(" FAILED: %0d", failed);
        $display("========================================");

        if (failed == 0)
            $display("ALL CSR TRAVERSAL TESTS PASSED");
        else
            $fatal(1, "CSR TRAVERSAL VERIFICATION FAILED");

        $finish;
    end

    // Global simulation timeout
    initial begin
        #100000;
        $fatal(1, "SIMULATION TIMEOUT");
    end

endmodule
