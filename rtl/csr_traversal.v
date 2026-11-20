module csr_traversal #(
    parameter NODE_WIDTH = 6,
    parameter EDGE_WIDTH = 9
)(
    input wire clk,
    input wire rst,
    input wire start,

    input wire [NODE_WIDTH-1:0] target_node,

    // Row pointer memory interface
    output reg [NODE_WIDTH:0] row_addr,
    input wire [EDGE_WIDTH-1:0] row_data,

    // Column index memory interface
    output wire [EDGE_WIDTH-1:0] col_addr,
    input wire [NODE_WIDTH-1:0] col_data,

    // Neighbor output interface
    output wire [NODE_WIDTH-1:0] neighbor_id,
    output wire neighbor_valid,
    input wire neighbor_ready,

    output reg busy,
    output reg done
);

    // FSM states
    localparam IDLE = 3'd0;
    localparam READ_START = 3'd1;
    localparam READ_END = 3'd2;
    localparam STREAM = 3'd3;
    localparam FINISH = 3'd4;

    // Internal registers
    reg [NODE_WIDTH-1:0] node_reg;

    reg [EDGE_WIDTH-1:0] current_edge;
    reg [EDGE_WIDTH-1:0] end_edge;

    reg [2:0] state;    

    always @(posedge clk) begin
    if (rst) begin
        state        <= IDLE;
        node_reg     <= 0;
        current_edge <= 0;
        end_edge     <= 0;
        row_addr     <= 0;
        busy         <= 0;
        done         <= 0;
    end else begin

        case (state)

            IDLE: begin
                done <= 0;
                if(start) begin
                    node_reg <= target_node;
                    busy <= 1;
                    row_addr <= {1'b0, target_node};
                    state <= READ_START;
                end
            end
            READ_START: begin
                current_edge <= row_data;
                row_addr <= {1'b0, node_reg} + 1'b1;
                state <= READ_END;
            end
            READ_END: begin
            end_edge <= row_data;
            if(current_edge >= row_data) begin
                state <= FINISH;
            end else begin
                state <= STREAM;
            end
            end
            STREAM: begin
                if(neighbor_ready)begin
                    if(current_edge +1'b1 == end_edge) begin
                        state <= FINISH;
                    end else begin
                        current_edge <= current_edge + 1'b1;
                    end
                end
            end
            FINISH: begin
                 busy  <= 0;
                done  <= 1;
                state <= IDLE;
            end
            default: begin
                state <= IDLE;
                busy  <= 0;
                done  <= 0;
            end

        endcase
    end
end

assign col_addr = current_edge;

assign neighbor_id = col_data;

assign neighbor_valid = (state == STREAM);

endmodule