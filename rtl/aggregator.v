
module aggregator #(
    parameter FEATURE_DIM = 8,
    parameter DATA_WIDTH  = 8,
    parameter ACC_WIDTH   = 32,
    parameter COUNT_WIDTH = 9
)(
    input wire clk,
    input wire rst,
    input wire en,
    input wire clear,

    input wire [(FEATURE_DIM*DATA_WIDTH)-1:0] feature_in,

    output wire [(FEATURE_DIM*ACC_WIDTH)-1:0] sum_out,
    output reg [COUNT_WIDTH-1:0] neighbor_count
);

    // Internal accumulator registers
    reg signed [ACC_WIDTH-1:0] accumulator
        [0:FEATURE_DIM-1];

    integer i;

    // Sequential control and accumulation logic
    always @(posedge clk) begin

        if (rst) begin

            for (i = 0; i < FEATURE_DIM; i = i + 1) begin
                accumulator[i] <= 0;
            end

            neighbor_count <= 0;

        end else if (clear) begin

            for (i = 0; i < FEATURE_DIM; i = i + 1) begin
                accumulator[i] <= 0;
            end

            neighbor_count <= 0;

        end else if (en) begin

            for (i = 0; i < FEATURE_DIM; i = i + 1) begin

                accumulator[i] <= accumulator[i] +
                    $signed(feature_in[i*DATA_WIDTH +: DATA_WIDTH]);

            end

            neighbor_count <= neighbor_count + 1'b1;

        end
    end

    // Flatten accumulator registers into output bus
    genvar j;

    generate
        for (j = 0; j < FEATURE_DIM; j = j + 1)
        begin : output_connections

            assign sum_out[j*ACC_WIDTH +: ACC_WIDTH]
                = accumulator[j];

        end
    endgenerate

endmodule
