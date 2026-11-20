
`timescale 1ns/1ps

module tb_graphcore_top;

    reg clk;
    reg rst;
    reg start;

    reg [5:0] target_node;
    reg [4:0] quant_shift;

    wire busy;
    wire done;
    wire [63:0] result;

    // Graph loading interface
    reg row_we;
    reg [6:0] row_wr_addr;
    reg [8:0] row_wr_data;

    reg col_we;
    reg [8:0] col_wr_addr;
    reg [5:0] col_wr_data;

    // Feature loading interface
    reg feature_we;
    reg [5:0] feature_wr_addr;
    reg [63:0] feature_wr_data;

    // Weight loading interface
    reg weight_we;
    reg [4:0] weight_wr_addr;
    reg [31:0] weight_wr_data;

    // Verification variables
    integer passed;
    integer failed;
    integer i;
    integer j;
    integer k;
    integer seed;

    // Reference model
    reg signed [7:0] features [0:63][0:7];
    reg signed [7:0] weights [0:15][0:7];

    reg [8:0] row_ptr [0:64];
    reg [5:0] col_idx [0:255];

    reg [63:0] expected_result;

    // Device under test
    graphcore_top dut (
        .clk(clk),
        .rst(rst),

        .start(start),
        .target_node(target_node),
        .quant_shift(quant_shift),

        .busy(busy),
        .done(done),
        .result(result),

        .row_we(row_we),
        .row_wr_addr(row_wr_addr),
        .row_wr_data(row_wr_data),

        .col_we(col_we),
        .col_wr_addr(col_wr_addr),
        .col_wr_data(col_wr_data),

        .feature_we(feature_we),
        .feature_wr_addr(feature_wr_addr),
        .feature_wr_data(feature_wr_data),

        .weight_we(weight_we),
        .weight_wr_addr(weight_wr_addr),
        .weight_wr_data(weight_wr_data)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // ========================================
    // Assertion task
    // ========================================

    task check;
        input condition;
        input [799:0] description;

        begin
            if (condition === 1'b1) begin
                passed = passed + 1;
                $display("[PASS] %0s", description);
            end else begin
                failed = failed + 1;
                $display("[FAIL] %0s", description);
            end
        end
    endtask

    // ========================================
    // Reset accelerator
    // ========================================

    task reset_dut;
        begin
            @(negedge clk);

            rst = 1;
            start = 0;

            row_we = 0;
            col_we = 0;
            feature_we = 0;
            weight_we = 0;

            repeat (3) @(posedge clk);

            @(negedge clk);

            rst = 0;
        end
    endtask

    // ========================================
    // Load graph memory
    // ========================================

    task load_graph;
        integer n;

        begin

            for (n = 0; n < 65; n = n + 1) begin

                @(negedge clk);

                row_we = 1;
                row_wr_addr = n;
                row_wr_data = row_ptr[n];

            end

            @(negedge clk);
            row_we = 0;

            for (n = 0; n < 256; n = n + 1) begin

                @(negedge clk);

                col_we = 1;
                col_wr_addr = n;
                col_wr_data = col_idx[n];

            end

            @(negedge clk);
            col_we = 0;

        end
    endtask

    // ========================================
    // Load feature memory
    // ========================================

    task load_features;

        integer n;
        integer f;

        reg [63:0] word_data;

        begin

            for (n = 0; n < 64; n = n + 1) begin

                word_data = 0;

                for (f = 0; f < 8; f = f + 1)
                    word_data[f*8 +: 8] =
                        features[n][f];

                @(negedge clk);

                feature_we = 1;
                feature_wr_addr = n;
                feature_wr_data = word_data;

            end

            @(negedge clk);
            feature_we = 0;

        end
    endtask

    // ========================================
    // Load weight memory
    // ========================================

    task load_weights;

        integer n;
        integer tile;
        integer f;

        reg [31:0] word_data;

        begin

            for (n = 0; n < 16; n = n + 1) begin

                for (tile = 0; tile < 2;
                     tile = tile + 1) begin

                    word_data = 0;

                    for (f = 0; f < 4; f = f + 1)
                        word_data[f*8 +: 8] =
                            weights[n][tile*4+f];

                    @(negedge clk);

                    weight_we = 1;
                    weight_wr_addr = n*2 + tile;
                    weight_wr_data = word_data;

                end

            end

            @(negedge clk);
            weight_we = 0;

        end
    endtask

    // ========================================
    // GraphSAGE behavioral reference model
    // ========================================

    task calculate_expected;

        input [5:0] node;
        input [4:0] shift_amount;

        integer f;
        integer e;
        integer o;
        integer m;
        integer count;
        integer neighbor;

        integer sum;
        integer acc;

        integer concat_vector [0:15];

        begin

            count = row_ptr[node+1] - row_ptr[node];

            // Target and neighborhood features
            for (f = 0; f < 8; f = f + 1) begin

                concat_vector[f] = features[node][f];

                sum = 0;

                for (e = row_ptr[node];
                     e < row_ptr[node+1];
                     e = e + 1) begin

                    neighbor = col_idx[e];

                    sum = sum + features[neighbor][f];

                end

                if (count == 0)
                    concat_vector[f+8] = 0;
                else
                    concat_vector[f+8] = sum / count;

            end

            expected_result = 0;

            // Matrix multiplication
            for (o = 0; o < 8; o = o + 1) begin

                acc = 0;

                for (m = 0; m < 16; m = m + 1)
                    acc = acc +
                          concat_vector[m] *
                          weights[m][o];

                // ReLU activation
                if (acc < 0)
                    acc = 0;

                // Quantization
                acc = acc >>> shift_amount;

                if (acc > 127)
                    acc = 127;

                expected_result[o*8 +: 8] =
                    acc[7:0];

            end

        end
    endtask

    // ========================================
    // Execute inference
    // ========================================

    task run_inference;

        input [5:0] node;
        input [4:0] shift_amount;

        // Attempt writes during inference
        input corrupt_memory;

        integer cycles;
        integer lane;

        begin

            calculate_expected(node, shift_amount);

            @(negedge clk);

            target_node = node;
            quant_shift = shift_amount;
            start = 1;

            @(posedge clk);
            #1;

            check(busy === 1'b1,
                  "Busy asserted after start");

            @(negedge clk);

            start = 0;

            // Attempt unauthorized memory writes
            if (corrupt_memory) begin

                row_we = 1;
                row_wr_addr = 1;
                row_wr_data = 0;

                col_we = 1;
                col_wr_addr = 0;
                col_wr_data = 63;

                feature_we = 1;
                feature_wr_addr = node;
                feature_wr_data = 64'hFFFFFFFFFFFFFFFF;

                weight_we = 1;
                weight_wr_addr = 0;
                weight_wr_data = 32'hFFFFFFFF;

                @(negedge clk);

                row_we = 0;
                col_we = 0;
                feature_we = 0;
                weight_we = 0;

            end

            cycles = 0;

            while (done !== 1'b1 &&
                   cycles < 1000) begin

                @(posedge clk);
                #1;

                cycles = cycles + 1;

            end

            check(done === 1'b1,
                  "Inference completed");

            check(busy === 1'b0,
                  "Busy deasserted");

            $display("Node     = %0d", node);
            $display("Shift    = %0d", shift_amount);
            $display("Expected = %h", expected_result);
            $display("Actual   = %h", result);

            for (lane = 0; lane < 8; lane = lane + 1) begin

                check(
                    result[lane*8 +: 8] ===
                    expected_result[lane*8 +: 8],
                    "Output feature matches reference"
                );

                $display(
                    "Y[%0d] Actual=%0d Expected=%0d",
                    lane,
                    $signed(result[lane*8 +: 8]),
                    $signed(expected_result[lane*8 +: 8])
                );

            end

            check(result === expected_result,
                  "Complete output vector matches");

            @(posedge clk);
            #1;

            check(done === 1'b0,
                  "Done pulse cleared");

        end
    endtask

    // ========================================
    // Main verification sequence
    // ========================================

    initial begin

        $dumpfile("graphcore_top_wave.vcd");
        $dumpvars(0, tb_graphcore_top);

        rst = 1;
        start = 0;

        target_node = 0;
        quant_shift = 0;

        row_we = 0;
        row_wr_addr = 0;
        row_wr_data = 0;

        col_we = 0;
        col_wr_addr = 0;
        col_wr_data = 0;

        feature_we = 0;
        feature_wr_addr = 0;
        feature_wr_data = 0;

        weight_we = 0;
        weight_wr_addr = 0;
        weight_wr_data = 0;

        passed = 0;
        failed = 0;
        seed = 12345;

        // Initialize graph
        for (i = 0; i < 65; i = i + 1)
            row_ptr[i] = 8;

        for (i = 0; i < 256; i = i + 1)
            col_idx[i] = 0;

        // Node 0: neighbors 1,2
        // Node 1: neighbors 0,2
        // Node 2: neighbors 0,1,3
        // Node 3: neighbor 2
        // Other nodes: isolated

        row_ptr[0] = 0;
        row_ptr[1] = 2;
        row_ptr[2] = 4;
        row_ptr[3] = 7;
        row_ptr[4] = 8;

        col_idx[0] = 1;
        col_idx[1] = 2;
        col_idx[2] = 0;
        col_idx[3] = 2;
        col_idx[4] = 0;
        col_idx[5] = 1;
        col_idx[6] = 3;
        col_idx[7] = 2;

        // Initialize features
        for (i = 0; i < 64; i = i + 1)
            for (j = 0; j < 8; j = j + 1)
                features[i][j] = (i+j) % 16 - 8;

        // Nonuniform signed weights
        for (i = 0; i < 16; i = i + 1)
            for (j = 0; j < 8; j = j + 1)
                weights[i][j] = (i*3+j) % 7 - 3;

        $display("====================================");
        $display(" GraphCore ASIC Final Verification");
        $display("====================================");

        // TEST 1: Reset
        reset_dut;

        check(busy === 1'b0, "Reset busy");
        check(done === 1'b0, "Reset done");
        check(result === 64'd0, "Reset result");

        load_graph;
        load_features;
        load_weights;

        // TEST 2: Basic inference
        $display("\nTEST 2: Basic inference");

        run_inference(0, 0, 0);
        run_inference(1, 0, 0);
        run_inference(2, 0, 0);
        run_inference(3, 0, 0);

        // TEST 3: Isolated nodes
        $display("\nTEST 3: Isolated nodes");

        run_inference(4, 0, 0);
        run_inference(63, 0, 0);

        // TEST 4: Quantization
        $display("\nTEST 4: Quantization");

        run_inference(2, 1, 0);
        run_inference(2, 2, 0);
        run_inference(2, 4, 0);
        run_inference(2, 31, 0);

        // TEST 5: Memory write protection
        $display("\nTEST 5: Memory protection");

        // Positive inputs make corruption observable
        for (i = 0; i < 64; i = i + 1)
            for (j = 0; j < 8; j = j + 1)
                features[i][j] = (i+j) % 8 + 1;

        for (i = 0; i < 16; i = i + 1)
            for (j = 0; j < 8; j = j + 1)
                weights[i][j] = 1;

        load_features;
        load_weights;

        run_inference(0, 1, 1);

        // Verify memory remains uncorrupted
        run_inference(0, 1, 0);

        // TEST 6: Positive saturation
        $display("\nTEST 6: Saturation");

        for (i = 0; i < 64; i = i + 1)
            for (j = 0; j < 8; j = j + 1)
                features[i][j] = 127;

        for (i = 0; i < 16; i = i + 1)
            for (j = 0; j < 8; j = j + 1)
                weights[i][j] = 127;

        load_features;
        load_weights;

        run_inference(0, 0, 0);
        run_inference(0, 12, 0);

        // TEST 7: Negative activation
        $display("\nTEST 7: Negative activation");

        for (i = 0; i < 16; i = i + 1)
            for (j = 0; j < 8; j = j + 1)
                weights[i][j] = -128;

        load_weights;

        run_inference(0, 0, 0);

        // TEST 8: Randomized inference
        $display("\nTEST 8: Randomized inference");

        for (k = 0; k < 10; k = k + 1) begin

            for (i = 0; i < 64; i = i + 1)
                for (j = 0; j < 8; j = j + 1)
                    features[i][j] =
                        $random(seed) % 32;

            for (i = 0; i < 16; i = i + 1)
                for (j = 0; j < 8; j = j + 1)
                    weights[i][j] =
                        $random(seed) % 16;

            load_features;
            load_weights;

            run_inference(k % 5, k % 5, 0);

        end

        // TEST 9: Reset during inference
        $display("\nTEST 9: Mid-inference reset");

        @(negedge clk);

        target_node = 2;
        quant_shift = 0;
        start = 1;

        @(negedge clk);
        start = 0;

        repeat (20) @(posedge clk);
        #1;

        check(busy === 1'b1,
              "Inference active before reset");

        reset_dut;

        check(busy === 1'b0, "Reset cancels inference");
        check(done === 1'b0, "Reset clears done");
        check(result === 64'd0, "Reset clears result");

        // Restart without reloading memory
        run_inference(2, 2, 0);

        // Final verification summary
        $display("\n====================================");
        $display(" FINAL GRAPHCORE VERIFICATION");
        $display("====================================");
        $display(" PASSED: %0d", passed);
        $display(" FAILED: %0d", failed);
        $display("====================================");

        if (failed == 0)
            $display("ALL GRAPHCORE TOP TESTS PASSED");
        else
            $fatal(1, "GRAPHCORE VERIFICATION FAILED");

        $finish;

    end

    // Global simulation timeout
    initial begin
        #2000000;
        $fatal(1, "SIMULATION TIMEOUT");
    end

endmodule
