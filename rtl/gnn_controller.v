
module gnn_controller (
    input wire clk,
    input wire rst,
    input wire start,

    input wire [5:0] target_node,
    input wire [4:0] quant_shift,

    output reg busy,
    output reg done,
    output reg [63:0] result,

    // Feature memory interface
    output wire [5:0] feature_rd_addr,
    input wire [63:0] feature_rd_data,

    // CSR traversal interface
    output wire csr_start,
    output wire [5:0] csr_target_node,

    input wire [5:0] neighbor_id,
    input wire neighbor_valid,
    output wire neighbor_ready,

    input wire csr_done,

    // Aggregator interface
    output wire agg_clear,
    output wire agg_en,
    output wire [63:0] agg_feature,

    // Mean normalizer interface
    output wire mean_start,
    input wire mean_done,
    input wire [63:0] mean_data,

    // Weight memory interface
    output wire [4:0] weight_rd_addr,
    input wire [31:0] weight_rd_data,

    // Systolic MAC array interface
    output wire mac_en,
    output wire mac_clear,

    output wire [31:0] mac_a_in,
    output wire [31:0] mac_b_in,

    input wire [511:0] mac_c_out,

    // ReLU and quantizer interface
    output wire [255:0] activation_in,
    output wire [4:0] activation_shift,

    input wire [63:0] quantized_data
);

    // =========================================
    // FSM states
    // =========================================

    localparam IDLE          = 4'd0;
    localparam FETCH_SELF    = 4'd1;
    localparam CLEAR_AGG     = 4'd2;
    localparam START_CSR     = 4'd3;
    localparam AGGREGATE     = 4'd4;
    localparam START_MEAN    = 4'd5;
    localparam WAIT_MEAN     = 4'd6;
    localparam LOAD_WEIGHTS  = 4'd7;
    localparam CLEAR_MAC     = 4'd8;
    localparam MAC_RUN       = 4'd9;
    localparam CAPTURE_MAC   = 4'd10;
    localparam POST_PROCESS  = 4'd11;
    localparam FINISH        = 4'd12;

    // =========================================
    // Internal registers
    // =========================================

    reg [3:0] state;

    // Saved inference configuration
    reg [5:0] node_reg;
    reg [4:0] shift_reg;

    // Feature vectors
    reg [63:0] self_features;
    reg [63:0] mean_features;

    wire [127:0] concat_features;

    // Select output features 0-3 or 4-7
    reg output_tile;

    // Weight-loading counter
    reg [3:0] weight_index;

    // Systolic execution counter
    reg [4:0] mac_cycle;

    // Weight buffer for current output tile
    reg [31:0] weight_buffer [0:15];

    // Weight delay registers
    reg [31:0] weight_delay1;
    reg [31:0] weight_delay2;
    reg [31:0] weight_delay3;

    wire [31:0] current_weights;
    wire [7:0] current_feature;

    // Eight INT32 output results
    reg [255:0] raw_result;

    // =========================================
    // Feature concatenation
    // =========================================

    // Features 0-7: target node
    // Features 8-15: neighborhood mean

    assign concat_features = {
        mean_features,
        self_features
    };

    // =========================================
    // Feature memory control
    // =========================================

    assign feature_rd_addr =
        (state == AGGREGATE)
        ? neighbor_id
        : node_reg;

    // =========================================
    // CSR traversal control
    // =========================================

    assign csr_start = (state == START_CSR);

    assign csr_target_node = node_reg;

    assign neighbor_ready =
        (state == AGGREGATE);

    // =========================================
    // Aggregator control
    // =========================================

    assign agg_clear =
        (state == CLEAR_AGG);

    assign agg_en =
        (state == AGGREGATE)
        && neighbor_valid
        && neighbor_ready;

    assign agg_feature = feature_rd_data;

    // =========================================
    // Mean normalizer control
    // =========================================

    assign mean_start =
        (state == START_MEAN);

    // =========================================
    // Weight memory control
    // =========================================

    // Address = 2*k + output_tile
    assign weight_rd_addr = {
        weight_index,
        output_tile
    };

    // =========================================
    // Systolic array control
    // =========================================

    assign mac_clear =
        (state == CLEAR_MAC);

    assign mac_en =
        (state == MAC_RUN);

    // Supply input features during cycles 0-15.
    // Supply zero during pipeline drain.

    assign current_feature =
        (mac_cycle < 16)
        ? concat_features[mac_cycle*8 +: 8]
        : 8'd0;

    assign current_weights =
        (mac_cycle < 16)
        ? weight_buffer[mac_cycle[3:0]]
        : 32'd0;

    // Only systolic row 0 is used for
    // single-node inference in V1.

    assign mac_a_in =
        (state == MAC_RUN)
        ? {24'd0, current_feature}
        : 32'd0;

    // Stagger the weights across the four columns.
    //
    // Column 0: no delay
    // Column 1: one cycle delay
    // Column 2: two cycle delay
    // Column 3: three cycle delay

    assign mac_b_in =
        (state == MAC_RUN)
        ? {
            weight_delay3[31:24],
            weight_delay2[23:16],
            weight_delay1[15:8],
            current_weights[7:0]
          }
        : 32'd0;

    // =========================================
    // ReLU and quantization interface
    // =========================================

    assign activation_in = raw_result;

    assign activation_shift = shift_reg;

    // =========================================
    // Sequential controller
    // =========================================

    always @(posedge clk) begin

        if (rst) begin

            state <= IDLE;

            busy <= 1'b0;
            done <= 1'b0;

            result <= 64'd0;

            node_reg <= 6'd0;
            shift_reg <= 5'd0;

            self_features <= 64'd0;
            mean_features <= 64'd0;

            output_tile <= 1'b0;

            weight_index <= 4'd0;
            mac_cycle <= 5'd0;

            weight_delay1 <= 32'd0;
            weight_delay2 <= 32'd0;
            weight_delay3 <= 32'd0;

            raw_result <= 256'd0;

        end else begin

            case (state)

                // =============================
                // Wait for inference request
                // =============================

                IDLE: begin

                    done <= 1'b0;
                    busy <= 1'b0;

                    if (start) begin

                        node_reg <= target_node;
                        shift_reg <= quant_shift;

                        busy <= 1'b1;

                        output_tile <= 1'b0;
                        weight_index <= 4'd0;
                        mac_cycle <= 5'd0;

                        raw_result <= 256'd0;

                        state <= FETCH_SELF;

                    end

                end

                // =============================
                // Retrieve target node features
                // =============================

                FETCH_SELF: begin

                    self_features <= feature_rd_data;

                    state <= CLEAR_AGG;

                end

                // =============================
                // Clear neighborhood accumulator
                // =============================

                CLEAR_AGG: begin

                    state <= START_CSR;

                end

                // =============================
                // Start graph traversal
                // =============================

                START_CSR: begin

                    state <= AGGREGATE;

                end

                // =============================
                // Stream and accumulate neighbors
                // =============================

                AGGREGATE: begin

                    if (csr_done) begin

                        state <= START_MEAN;

                    end

                end

                // =============================
                // Start mean normalization
                // =============================

                START_MEAN: begin

                    state <= WAIT_MEAN;

                end

                // =============================
                // Wait for normalized features
                // =============================

                WAIT_MEAN: begin

                    if (mean_done) begin

                        mean_features <= mean_data;

                        weight_index <= 4'd0;

                        state <= LOAD_WEIGHTS;

                    end

                end

                // =============================
                // Load current weight tile
                // =============================

                LOAD_WEIGHTS: begin

                    weight_buffer[weight_index]
                        <= weight_rd_data;

                    if (weight_index == 4'd15) begin

                        weight_index <= 4'd0;

                        state <= CLEAR_MAC;

                    end else begin

                        weight_index <=
                            weight_index + 1'b1;

                    end

                end

                // =============================
                // Clear MAC accumulators
                // =============================

                CLEAR_MAC: begin

                    mac_cycle <= 5'd0;

                    weight_delay1 <= 32'd0;
                    weight_delay2 <= 32'd0;
                    weight_delay3 <= 32'd0;

                    state <= MAC_RUN;

                end

                // =============================
                // Systolic matrix multiplication
                // =============================

                MAC_RUN: begin

                    // Advance weight skew pipeline
                    weight_delay1 <= current_weights;
                    weight_delay2 <= weight_delay1;
                    weight_delay3 <= weight_delay2;

                    // 16 input cycles and
                    // 6 pipeline drain cycles

                    if (mac_cycle == 5'd21) begin

                        state <= CAPTURE_MAC;

                    end else begin

                        mac_cycle <= mac_cycle + 1'b1;

                    end

                end

                // =============================
                // Capture output tile
                // =============================

                CAPTURE_MAC: begin

                    // MAC row 0, columns 0-3:
                    // c_out[127:0]

                    if (output_tile == 1'b0) begin

                        raw_result[127:0]
                            <= mac_c_out[127:0];

                        output_tile <= 1'b1;

                        weight_index <= 4'd0;

                        state <= LOAD_WEIGHTS;

                    end else begin

                        raw_result[255:128]
                            <= mac_c_out[127:0];

                        state <= POST_PROCESS;

                    end

                end

                // =============================
                // Capture activated INT8 outputs
                // =============================

                POST_PROCESS: begin

                    result <= quantized_data;

                    state <= FINISH;

                end

                // =============================
                // Signal inference completion
                // =============================

                FINISH: begin

                    busy <= 1'b0;
                    done <= 1'b1;

                    state <= IDLE;

                end

                // =============================
                // Illegal state recovery
                // =============================

                default: begin

                    state <= IDLE;

                    busy <= 1'b0;
                    done <= 1'b0;

                end

            endcase

        end

    end

endmodule
