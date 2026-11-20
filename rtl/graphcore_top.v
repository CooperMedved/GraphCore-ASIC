
module graphcore_top (
    input wire clk,
    input wire rst,

    // =========================================
    // Inference control interface
    // =========================================

    input wire start,
    input wire [5:0] target_node,
    input wire [4:0] quant_shift,

    output wire busy,
    output wire done,
    output wire [63:0] result,

    // =========================================
    // Graph row pointer loading interface
    // =========================================

    input wire row_we,
    input wire [6:0] row_wr_addr,
    input wire [8:0] row_wr_data,

    // =========================================
    // Graph column index loading interface
    // =========================================

    input wire col_we,
    input wire [8:0] col_wr_addr,
    input wire [5:0] col_wr_data,

    // =========================================
    // Feature memory loading interface
    // =========================================

    input wire feature_we,
    input wire [5:0] feature_wr_addr,
    input wire [63:0] feature_wr_data,

    // =========================================
    // Weight memory loading interface
    // =========================================

    input wire weight_we,
    input wire [4:0] weight_wr_addr,
    input wire [31:0] weight_wr_data
);

    // =========================================
    // Internal feature memory signals
    // =========================================

    wire [5:0] feature_rd_addr;
    wire [63:0] feature_rd_data;

    // =========================================
    // Internal graph memory signals
    // =========================================

    wire [6:0] row_addr;
    wire [8:0] row_data;

    wire [8:0] col_addr;
    wire [5:0] col_data;

    // =========================================
    // Internal CSR traversal signals
    // =========================================

    wire csr_start;
    wire [5:0] csr_target_node;

    wire [5:0] neighbor_id;
    wire neighbor_valid;
    wire neighbor_ready;

    wire csr_busy;
    wire csr_done;

    // =========================================
    // Internal aggregation signals
    // =========================================

    wire agg_clear;
    wire agg_en;

    wire [63:0] agg_feature;

    wire [255:0] agg_sum;
    wire [8:0] neighbor_count;

    // =========================================
    // Internal mean normalization signals
    // =========================================

    wire mean_start;
    wire mean_busy;
    wire mean_done;

    wire [63:0] mean_data;

    // =========================================
    // Internal weight memory signals
    // =========================================

    wire [4:0] weight_rd_addr;
    wire [31:0] weight_rd_data;

    // =========================================
    // Internal systolic MAC signals
    // =========================================

    wire mac_en;
    wire mac_clear;

    wire [31:0] mac_a_in;
    wire [31:0] mac_b_in;

    wire [511:0] mac_c_out;

    // =========================================
    // Internal activation signals
    // =========================================

    wire [255:0] activation_in;
    wire [255:0] relu_data;

    wire [4:0] activation_shift;

    wire [63:0] quantized_data;

    // =========================================
    // Memory write protection
    // =========================================

    // Prevent the host from modifying memory
    // during an active inference operation
    // or while reset is asserted.

    wire load_allowed;

    assign load_allowed = !busy && !rst && !start;

    // =========================================
    // GNN controller
    // =========================================

    gnn_controller u_controller (
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
    // Graph memory
    // =========================================

    graph_memory #(
        .MAX_NODES(64),
        .MAX_EDGES(256),
        .NODE_WIDTH(6),
        .EDGE_WIDTH(9)
    ) u_graph_memory (
        .clk(clk),

        .row_we(row_we && load_allowed),
        .row_wr_addr(row_wr_addr),
        .row_wr_data(row_wr_data),

        .col_we(col_we && load_allowed),
        .col_wr_addr(col_wr_addr),
        .col_wr_data(col_wr_data),

        .row_addr(row_addr),
        .row_data(row_data),

        .col_addr(col_addr),
        .col_data(col_data)
    );

    // =========================================
    // CSR traversal engine
    // =========================================

    csr_traversal #(
        .NODE_WIDTH(6),
        .EDGE_WIDTH(9)
    ) u_csr (
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
    // Feature memory
    // =========================================

    feature_memory #(
        .MAX_NODES(64),
        .NODE_WIDTH(6),
        .FEATURE_DIM(8),
        .DATA_WIDTH(8)
    ) u_feature_memory (
        .clk(clk),

        .we(feature_we && load_allowed),
        .wr_addr(feature_wr_addr),
        .wr_data(feature_wr_data),

        .rd_addr(feature_rd_addr),
        .rd_data(feature_rd_data)
    );

    // =========================================
    // Neighborhood aggregator
    // =========================================

    aggregator #(
        .FEATURE_DIM(8),
        .DATA_WIDTH(8),
        .ACC_WIDTH(32),
        .COUNT_WIDTH(9)
    ) u_aggregator (
        .clk(clk),
        .rst(rst),

        .en(agg_en),
        .clear(agg_clear),

        .feature_in(agg_feature),

        .sum_out(agg_sum),
        .neighbor_count(neighbor_count)
    );

    // =========================================
    // Mean normalization engine
    // =========================================

    mean_normalizer #(
        .FEATURE_DIM(8),
        .DATA_WIDTH(8),
        .ACC_WIDTH(32),
        .COUNT_WIDTH(9)
    ) u_mean_normalizer (
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
    // Neural network weight memory
    // =========================================

    weight_memory #(
        .INPUT_DIM(16),
        .OUTPUT_DIM(8),
        .ARRAY_SIZE(4),
        .DATA_WIDTH(8),
        .ADDR_WIDTH(5)
    ) u_weight_memory (
        .clk(clk),

        .we(weight_we && load_allowed),
        .wr_addr(weight_wr_addr),
        .wr_data(weight_wr_data),

        .rd_addr(weight_rd_addr),
        .rd_data(weight_rd_data)
    );

    // =========================================
    // 4x4 systolic MAC array
    // =========================================

    mac_array #(
        .ARRAY_SIZE(4),
        .DATA_WIDTH(8),
        .ACC_WIDTH(32)
    ) u_mac_array (
        .clk(clk),
        .rst(rst),

        .en(mac_en),
        .clear(mac_clear),

        .a_in(mac_a_in),
        .b_in(mac_b_in),

        .c_out(mac_c_out)
    );

    // =========================================
    // ReLU activation
    // =========================================

    relu #(
        .FEATURE_DIM(8),
        .ACC_WIDTH(32)
    ) u_relu (
        .data_in(activation_in),
        .data_out(relu_data)
    );

    // =========================================
    // INT32-to-INT8 quantization
    // =========================================

    quantizer #(
        .FEATURE_DIM(8),
        .ACC_WIDTH(32),
        .DATA_WIDTH(8),
        .SHIFT_WIDTH(5)
    ) u_quantizer (
        .data_in(relu_data),
        .shift(activation_shift),
        .data_out(quantized_data)
    );

endmodule
