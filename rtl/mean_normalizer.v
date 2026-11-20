module mean_normalizer #(
    parameter FEATURE_DIM = 8,
    parameter DATA_WIDTH  = 8,
    parameter ACC_WIDTH   = 32,
    parameter COUNT_WIDTH = 9
)(
    input wire clk,
    input wire rst,
    input wire start,

    input wire [(FEATURE_DIM*ACC_WIDTH)-1:0] sum_in,
    input wire [COUNT_WIDTH-1:0] neighbor_count,

    output reg [(FEATURE_DIM*DATA_WIDTH)-1:0] mean_out,
    output reg busy,
    output reg done
);
  // FSM states
localparam IDLE = 2'd0;
localparam DIVIDE = 2'd1;
localparam FINISH = 2'd2;

    // Internal registers
reg [1:0] state;

reg [31:0] feature_index;

wire signed [ACC_WIDTH-1:0] selected_sum;
wire signed [COUNT_WIDTH:0] signed_count;
wire signed [ACC_WIDTH-1:0] quotient;

 // Division datapath
assign selected_sum = $signed(sum_in[feature_index*ACC_WIDTH +: ACC_WIDTH]);
assign signed_count = $signed({1'b0, neighbor_count});
assign quotient = (neighbor_count == 0) ? 0  : selected_sum / signed_count; // Avoid division by zero

   
always @(posedge clk) begin
    if (rst) begin
        state <= IDLE;
        feature_index <= 0;
        mean_out <= 0;
        busy <= 0;
        done <= 0;
    end else begin
        case (state)
            IDLE: begin
                done <= 0;
                if (start) begin
                    state <= DIVIDE;
                    feature_index <= 0;
                    busy <= 1;
                    
                end
            end

            DIVIDE: begin
                mean_out[feature_index*DATA_WIDTH +: DATA_WIDTH] <= quotient[DATA_WIDTH-1:0];
                if (feature_index == FEATURE_DIM - 1) begin
                    state <= FINISH;
                end else begin
                    feature_index <= feature_index + 1;
                end
            end

            FINISH: begin
                busy <= 0;
                done <= 1;
                state <= IDLE; // Return to IDLE after finishing
            end

            default: state <= IDLE; // Default case to handle unexpected states
        endcase
    end
end

   

endmodule