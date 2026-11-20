
`timescale 1ns/1ps

module tb_gnn_controller;

    reg clk;
    reg rst;
    reg start;

    reg [5:0] target_node;
    reg [4:0] quant_shift;

    wire busy;
    wire done;
    wire [63:0] result;

    // =========================================
    // Feature memory signals
    // =========================================

    reg feature_we;
    reg [5:0] feature_wr_addr;
    reg [63:0] feature_wr_data;

    wire [5:0] feature_rd_addr;
    wire [63:0] feature_rd_data;

    // =========================================
    // Graph memory signals
    // =========================================

    reg row_we;
    reg [6:0] row_wr_addr;
    reg [8:0] row_wr_data;

    reg col_we;
    reg [8:0] col_wr_addr;
    reg [5:0] col_wr_data;

    wire [6:0] row_addr;
    wire [8:0] row_data;

    wire [8:0] col_addr;
    wire [5:0] col_data;

    // =========================================
    // CSR traversal signals
    // =========================================

    wire csr_start;
    wire [5:0] csr_target_node;

    wire [5:0] neighbor_id;
    wire neighbor_valid;
    wire neighbor_ready;

    wire csr_busy;
    wire csr_done;

    // =========================================
    // Aggregator signals
    // =========================================

    wire agg_clear;
    wire agg_en;
    wire [63:0] agg_feature;

    wire [255:0] agg_sum;
    wire [8:0] neighbor_count;

    // =========================================
    // Mean normalizer signals
    // =========================================

    wire mean_start;
    wire mean_busy;
    wire mean_done;
    wire [63:0] mean_data;

    // =========================================
    // Weight memory signals
    // =========================================

    reg weight_we;
    reg [4:0] weight_wr_addr;
    reg [31:0] weight_wr_data;

    wire [4:0] weight_rd_addr;
    wire [31:0] weight_rd_data;

    // =========================================
    // MAC array signals
    // =========================================

    wire mac_en;
    wire mac_clear;

    wire [31:0] mac_a_in;
    wire [31:0] mac_b_in;

    wire [511:0] mac_c_out;

    // =========================================
    // Activation and quantization signals
    // =========================================

    wire [255:0] activation_in;
    wire [255:0] relu_data;

    wire [4:0] activation_shift;
    wire [63:0] quantized_data;

    // =========================================
    // Verification variables
    // =========================================

    integer passed;
    integer failed;
    integer i;
    integer j;
    integer k;
    integer tile;
    integer seed;

    reg [63:0] feature_word;
    reg [31:0] weight_word;

    // Reference model storage

    reg signed [7:0] ref_features [0:63][0:7];
    reg signed [7:0] ref_weights [0:15][0:7];

    reg [8:0] ref_row [0:64];
    reg [5:0] ref_col [0:255];

    reg signed [31:0] ref_mean [0:7];
    reg signed [31:0] ref_concat [0:15];
    reg signed [31:0] ref_raw [0:7];

    reg [63:0] expected_result;

    // =========================================
    // Clock generation
    // =========================================

    initial clk = 0;
    always #5 clk = ~clk;

    // =========================================
    // Controller under test
    // =========================================

    gnn_controller dut (
        .clk(clk),
        .rst(rst),
        .start(start),

        .target_node(target_node),
        .quant_shift(quant_shift),

        .busy(busy),
        .done(done),
        .result(result),

        .feature_rd_addr(feature_rd_addr),
        .feature_rd_data(feature_rd_data),

        .csr_start(csr_start),
        .csr_target_node(csr_target_node),

        .neighbor_id(neighbor_id),
        .neighbor_valid(neighbor_valid),
        .neighbor_ready(neighbor_ready),

        .csr_done(csr_done),

        .agg_clear(agg_clear),
        .agg_en(agg_en),
        .agg_feature(agg_feature),

        .mean_start(mean_start),
        .mean_done(mean_done),
        .mean_data(mean_data),

        .weight_rd_addr(weight_rd_addr),
        .weight_rd_data(weight_rd_data),

        .mac_en(mac_en),
        .mac_clear(mac_clear),

        .mac_a_in(mac_a_in),
        .mac_b_in(mac_b_in),
        .mac_c_out(mac_c_out),

        .activation_in(activation_in),
        .activation_shift(activation_shift),

        .quantized_data(quantized_data)
    );

    // =========================================
    // Feature memory
    // =========================================

    feature_memory feature_mem (
        .clk(clk),

        .we(feature_we),
        .wr_addr(feature_wr_addr),
        .wr_data(feature_wr_data),

        .rd_addr(feature_rd_addr),
        .rd_data(feature_rd_data)
    );

    // =========================================
    // Graph memory
    // =========================================

    graph_memory graph_mem (
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

    // =========================================
    // CSR traversal
    // =========================================

    csr_traversal csr (
        .clk(clk),
        .rst(rst),
        .start(csr_start),

        .target_node(csr_target_node),

        .row_addr(row_addr),
        .row_data(row_data),

        .col_addr(col_addr),
        .col_data(col_data),

        .neighbor_id(neighbor_id),
        .neighbor_valid(neighbor_valid),
        .neighbor_ready(neighbor_ready),

        .busy(csr_busy),
        .done(csr_done)
    );

    // =========================================
    // Feature aggregator
    // =========================================

    aggregator agg (
        .clk(clk),
        .rst(rst),
        .en(agg_en),
        .clear(agg_clear),

        .feature_in(agg_feature),

        .sum_out(agg_sum),
        .neighbor_count(neighbor_count)
    );

    // =========================================
    // Mean normalizer
    // =========================================

    mean_normalizer mean_norm (
        .clk(clk),
        .rst(rst),
        .start(mean_start),

        .sum_in(agg_sum),
        .neighbor_count(neighbor_count),

        .mean_out(mean_data),

        .busy(mean_busy),
        .done(mean_done)
    );

    // =========================================
    // Weight memory
    // =========================================

    weight_memory weight_mem (
        .clk(clk),

        .we(weight_we),
        .wr_addr(weight_wr_addr),
        .wr_data(weight_wr_data),

        .rd_addr(weight_rd_addr),
        .rd_data(weight_rd_data)
    );

    // =========================================
    // Systolic MAC array
    // =========================================

    mac_array mac (
        .clk(clk),
        .rst(rst),

        .en(mac_en),
        .clear(mac_clear),

        .a_in(mac_a_in),
        .b_in(mac_b_in),

        .c_out(mac_c_out)
    );

    // =========================================
    // ReLU
    // =========================================

    relu activation (
        .data_in(activation_in),
        .data_out(relu_data)
    );

    // =========================================
    // Quantizer
    // =========================================

    quantizer quant (
        .data_in(relu_data),
        .shift(activation_shift),
        .data_out(quantized_data)
    );

    // =========================================
    // Assertion task
    // =========================================

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

    // =========================================
    // Reset task
    // =========================================

    task reset_dut;

        begin

            @(negedge clk);

            rst = 1;
            start = 0;

            repeat (3) @(posedge clk);

            @(negedge clk);

            rst = 0;

        end
    endtask

    // =========================================
    // Load graph memory
    // =========================================

    task load_graph;

        integer m;

        begin

            for (m = 0; m < 65; m = m + 1) begin

                @(negedge clk);

                row_we = 1;
                row_wr_addr = m;
                row_wr_data = ref_row[m];

            end

            @(negedge clk);
            row_we = 0;

            for (m = 0; m < 256; m = m + 1) begin

                @(negedge clk);

                col_we = 1;
                col_wr_addr = m;
                col_wr_data = ref_col[m];

            end

            @(negedge clk);
            col_we = 0;

        end
    endtask

    // =========================================
    // Load node feature memory
    // =========================================

    task load_features;

        integer n;
        integer f;

        begin

            for (n = 0; n < 64; n = n + 1) begin

                feature_word = 0;

                for (f = 0; f < 8; f = f + 1) begin

                    feature_word[f*8 +: 8] =
                        ref_features[n][f];

                end

                @(negedge clk);

                feature_we = 1;
                feature_wr_addr = n;
                feature_wr_data = feature_word;

            end

            @(negedge clk);
            feature_we = 0;

        end
    endtask

    // =========================================
    // Load weight memory
    // =========================================

    task load_weights;

        integer m;
        integer t;
        integer w;

        begin

            for (m = 0; m < 16; m = m + 1) begin

                for (t = 0; t < 2; t = t + 1) begin

                    weight_word = 0;

                    for (w = 0; w < 4; w = w + 1) begin

                        weight_word[w*8 +: 8] =
                            ref_weights[m][t*4+w];

                    end

                    @(negedge clk);

                    weight_we = 1;
                    weight_wr_addr = m*2+t;
                    weight_wr_data = weight_word;

                end

            end

            @(negedge clk);
            weight_we = 0;

        end
    endtask

    // =========================================
    // Behavioral GraphSAGE reference model
    // =========================================

    task calculate_expected;

        input [5:0] node;
        input [4:0] shift_amount;

        integer f;
        integer e;
        integer m;
        integer o;
        integer count;
        integer neighbor;

        reg signed [31:0] sum;
        reg signed [31:0] acc;
        reg signed [31:0] activated;
        reg signed [31:0] scaled;

        begin

            count = ref_row[node+1] - ref_row[node];

            // Calculate neighborhood mean

            for (f = 0; f < 8; f = f + 1) begin

                sum = 0;

                for (e = ref_row[node];
                     e < ref_row[node+1];
                     e = e + 1) begin

                    neighbor = ref_col[e];

                    sum = sum + ref_features[neighbor][f];

                end

                if (count == 0)
                    ref_mean[f] = 0;
                else
                    ref_mean[f] = sum / count;

            end

            // Concatenate self and neighbor features

            for (f = 0; f < 8; f = f + 1) begin

                ref_concat[f] =
                    ref_features[node][f];

                ref_concat[f+8] =
                    ref_mean[f];

            end

            // Matrix-vector multiplication

            expected_result = 0;

            for (o = 0; o < 8; o = o + 1) begin

                acc = 0;

                for (m = 0; m < 16; m = m + 1) begin

                    acc = acc +
                        ref_concat[m] *
                        ref_weights[m][o];

                end

                ref_raw[o] = acc;

                // ReLU

                if (acc < 0)
                    activated = 0;
                else
                    activated = acc;

                // Quantization

                scaled = activated >>> shift_amount;

                if (scaled > 127)
                    scaled = 127;
                else if (scaled < -128)
                    scaled = -128;

                expected_result[o*8 +: 8] =
                    scaled[7:0];

            end

        end
    endtask

    // =========================================
    // Run complete inference
    // =========================================

    task run_inference;

        input [5:0] node;
        input [4:0] shift_amount;

        integer cycles;
        integer lane;
        integer mac_cycles;
        integer mac_clears;
        integer accepted_neighbors;

        reg signed [31:0] actual_raw;
        reg signed [7:0] actual_feature;
        reg signed [7:0] expected_feature;

        begin

            calculate_expected(node, shift_amount);

            @(negedge clk);

            target_node = node;
            quant_shift = shift_amount;
            start = 1;

            @(posedge clk);
            #1;

            check(busy === 1'b1,
                  "Controller busy after start");

            @(negedge clk);
            start = 0;

            cycles = 0;
            mac_cycles = 0;
            mac_clears = 0;
            accepted_neighbors = 0;

            while (done !== 1'b1 &&
                   cycles < 1000) begin

                @(posedge clk);

                if (agg_en)
                    accepted_neighbors =
                        accepted_neighbors + 1;

                if (mac_en)
                    mac_cycles = mac_cycles + 1;

                if (mac_clear)
                    mac_clears = mac_clears + 1;

                #1;

                cycles = cycles + 1;

            end

            $display("Node=%0d Shift=%0d Cycles=%0d",
                     node, shift_amount, cycles+1);

            check(done === 1'b1,
                  "Inference completed");

            check(busy === 1'b0,
                  "Controller busy deasserted");

            check(
                accepted_neighbors ==
                ref_row[node+1] - ref_row[node],
                "Correct number of neighbor handshakes"
            );

            check(mac_cycles == 44,
                  "Two 22-cycle MAC operations");

            check(mac_clears == 2,
                  "MAC accumulator cleared twice");

            // Check unquantized matrix multiplication

            for (lane = 0; lane < 8; lane = lane + 1) begin

                actual_raw =
                    $signed(
                        activation_in[lane*32 +: 32]
                    );

                if (actual_raw === ref_raw[lane]) begin

                    passed = passed + 1;

                    $display(
                        "[PASS] RAW[%0d]=%0d",
                        lane, actual_raw
                    );

                end else begin

                    failed = failed + 1;

                    $display(
                        "[FAIL] RAW[%0d]=%0d Expected=%0d",
                        lane, actual_raw, ref_raw[lane]
                    );

                end

            end

            // Verify final INT8 results

            for (lane = 0; lane < 8; lane = lane + 1) begin

                actual_feature =
                    $signed(result[lane*8 +: 8]);

                expected_feature =
                    $signed(expected_result[lane*8 +: 8]);

                if (actual_feature === expected_feature) begin

                    passed = passed + 1;

                    $display(
                        "[PASS] Y[%0d]=%0d",
                        lane, actual_feature
                    );

                end else begin

                    failed = failed + 1;

                    $display(
                        "[FAIL] Y[%0d]=%0d Expected=%0d",
                        lane, actual_feature,
                        expected_feature
                    );

                end

            end

            check(
                result === expected_result,
                "Complete 64-bit output matches reference"
            );

            $display("Expected = %h", expected_result);
            $display("Actual   = %h", result);

            @(posedge clk);
            #1;

            check(done === 1'b0,
                  "Done is a one-cycle pulse");

        end
    endtask

    // =========================================
    // Main test sequence
    // =========================================

    initial begin

        $dumpfile("gnn_controller_wave.vcd");
        $dumpvars(0, tb_gnn_controller);

        rst = 1;
        start = 0;

        target_node = 0;
        quant_shift = 0;

        feature_we = 0;
        feature_wr_addr = 0;
        feature_wr_data = 0;

        row_we = 0;
        row_wr_addr = 0;
        row_wr_data = 0;

        col_we = 0;
        col_wr_addr = 0;
        col_wr_data = 0;

        weight_we = 0;
        weight_wr_addr = 0;
        weight_wr_data = 0;

        passed = 0;
        failed = 0;
        seed = 12345;

        // Initialize reference graph

        for (i = 0; i < 65; i = i + 1)
            ref_row[i] = 8;

        for (i = 0; i < 256; i = i + 1)
            ref_col[i] = 0;

        // Node 0: 1,2
        // Node 1: 0,2
        // Node 2: 0,1,3
        // Node 3: 2
        // Node 4-63: isolated

        ref_row[0] = 0;
        ref_row[1] = 2;
        ref_row[2] = 4;
        ref_row[3] = 7;
        ref_row[4] = 8;

        ref_col[0] = 1;
        ref_col[1] = 2;
        ref_col[2] = 0;
        ref_col[3] = 2;
        ref_col[4] = 0;
        ref_col[5] = 1;
        ref_col[6] = 3;
        ref_col[7] = 2;

        // Initialize features

        for (i = 0; i < 64; i = i + 1) begin

            for (j = 0; j < 8; j = j + 1) begin

                ref_features[i][j] =
                    (i+j) % 16 - 8;

            end

        end

        // Initialize weights

        for (i = 0; i < 16; i = i + 1) begin

            for (j = 0; j < 8; j = j + 1) begin

                ref_weights[i][j] = 1;

            end

        end

        $display("========================================");
        $display(" GraphCore Controller Integration Test");
        $display("========================================");

        reset_dut;

        check(busy === 1'b0, "Reset busy");
        check(done === 1'b0, "Reset done");
        check(result === 64'd0, "Reset result");

        load_graph;
        load_features;
        load_weights;

        // =====================================
        // TEST 1: Basic inference
        // =====================================

        $display("\nTEST 1: Basic inference");

        run_inference(0, 0);

        // =====================================
        // TEST 2: Multiple neighbors
        // =====================================

        $display("\nTEST 2: Multiple neighbors");

        run_inference(2, 0);

        // =====================================
        // TEST 3: Single neighbor
        // =====================================

        $display("\nTEST 3: Single neighbor");

        run_inference(3, 0);

        // =====================================
        // TEST 4: Isolated node
        // =====================================

        $display("\nTEST 4: Isolated node");

        run_inference(4, 0);

        // =====================================
        // TEST 5: Maximum node address
        // =====================================

        $display("\nTEST 5: Maximum node address");

        run_inference(63, 0);

        // =====================================
        // TEST 6: Identity transformation
        // =====================================

        $display("\nTEST 6: Identity weights");

        for (i = 0; i < 16; i = i + 1) begin

            for (j = 0; j < 8; j = j + 1) begin

                if (i == j)
                    ref_weights[i][j] = 1;
                else
                    ref_weights[i][j] = 0;

            end

        end

        load_weights;

        run_inference(63, 0);

        // =====================================
        // TEST 7: Neighborhood-only weights
        // =====================================

        $display("\nTEST 7: Neighborhood only");

        for (i = 0; i < 16; i = i + 1) begin

            for (j = 0; j < 8; j = j + 1) begin

                if (i == j+8)
                    ref_weights[i][j] = 1;
                else
                    ref_weights[i][j] = 0;

            end

        end

        load_weights;

        run_inference(2, 0);
        run_inference(4, 0);

        // =====================================
        // TEST 8: Positive saturation
        // =====================================

        $display("\nTEST 8: Positive saturation");

        for (i = 0; i < 64; i = i + 1)
            for (j = 0; j < 8; j = j + 1)
                ref_features[i][j] = 127;

        for (i = 0; i < 16; i = i + 1)
            for (j = 0; j < 8; j = j + 1)
                ref_weights[i][j] = 127;

        load_features;
        load_weights;

        run_inference(0, 0);

        // =====================================
        // TEST 9: Quantization scaling
        // =====================================

        $display("\nTEST 9: Quantization scaling");

        run_inference(0, 8);
        run_inference(0, 12);
        run_inference(0, 16);
        run_inference(0, 31);

        // =====================================
        // TEST 10: Negative activation
        // =====================================

        $display("\nTEST 10: Negative activation");

        for (i = 0; i < 16; i = i + 1)
            for (j = 0; j < 8; j = j + 1)
                ref_weights[i][j] = -128;

        load_weights;

        run_inference(0, 0);

        // =====================================
        // TEST 11: Randomized inference
        // =====================================

        $display("\nTEST 11: Randomized inference");

        for (k = 0; k < 10; k = k + 1) begin

            for (i = 0; i < 64; i = i + 1) begin

                for (j = 0; j < 8; j = j + 1) begin

                    ref_features[i][j] =
                        $random(seed) % 32;

                end

            end

            for (i = 0; i < 16; i = i + 1) begin

                for (j = 0; j < 8; j = j + 1) begin

                    ref_weights[i][j] =
                        $random(seed) % 16;

                end

            end

            load_features;
            load_weights;

            run_inference(k % 5, k % 5);

        end

        // =====================================
        // TEST 12: Reset during inference
        // =====================================

        $display("\nTEST 12: Mid-inference reset");

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

        check(busy === 1'b0,
              "Reset clears controller busy");

        check(done === 1'b0,
              "Reset clears done");

        check(result === 64'd0,
              "Reset clears result");

        // Verify restart after reset

        run_inference(2, 2);

        // =====================================
        // Final summary
        // =====================================

        $display("\n========================================");
        $display(" Controller Integration Results");
        $display("========================================");

        $display(" PASSED: %0d", passed);
        $display(" FAILED: %0d", failed);

        $display("========================================");

        if (failed == 0)
            $display("ALL GNN CONTROLLER TESTS PASSED");
        else
            $fatal(1, "GNN CONTROLLER VERIFICATION FAILED");

        $finish;

    end

    // Global timeout

    initial begin

        #1000000;
        $fatal(1, "SIMULATION TIMEOUT");

    end

endmodule
