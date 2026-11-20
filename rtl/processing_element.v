module processing_element#(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH = 32
)(
    input wire clk,
    input wire rst,
    input wire en,
    input wire clear,
    
    input wire signed [DATA_WIDTH-1:0] a_in,
    input wire signed [DATA_WIDTH-1:0] b_in,

    output reg signed [DATA_WIDTH-1:0] a_out,
    output reg signed [DATA_WIDTH-1:0] b_out,
    output reg signed [ACC_WIDTH-1:0] acc_out
);

wire signed [(2*DATA_WIDTH)-1:0] product;

assign product = a_in * b_in;

always @(posedge clk) begin
    if(rst) begin
        a_out <= 0;
        b_out <= 0;
        acc_out <= 0;
    end else if(clear) begin
        acc_out <=0;
    end else if(en) begin
        a_out <= a_in;
        b_out <= b_in;
        acc_out <= acc_out + product;
    end

end


endmodule