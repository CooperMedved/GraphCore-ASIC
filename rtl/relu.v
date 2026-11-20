module relu #(
    parameter FEATURE_DIM = 8,
    parameter ACC_WIDTH = 32
)(
    input wire [(FEATURE_DIM*ACC_WIDTH)-1:0] data_in,
    output wire [(FEATURE_DIM*ACC_WIDTH)-1:0] data_out
);

    // Generate parallel ReLU units

    genvar i;

generate
    for (i = 0; i < FEATURE_DIM; i = i + 1) begin : relu_units

        wire signed [ACC_WIDTH-1:0] feature;

        // Extract the current feature
        assign feature = data_in[i*ACC_WIDTH +: ACC_WIDTH];

        // Apply ReLU
        assign data_out[i*ACC_WIDTH +: ACC_WIDTH] =
            feature[ACC_WIDTH-1] ? {ACC_WIDTH{1'b0}} : feature;

    end
endgenerate

endmodule