
module quantizer #(
    parameter FEATURE_DIM = 8,
    parameter ACC_WIDTH = 32,
    parameter DATA_WIDTH = 8,
    parameter SHIFT_WIDTH = 5
)(
    input wire [(FEATURE_DIM*ACC_WIDTH)-1:0] data_in,

    input wire [SHIFT_WIDTH-1:0] shift,

    output wire [(FEATURE_DIM*DATA_WIDTH)-1:0] data_out
);

    // Saturation constants
    localparam signed [ACC_WIDTH-1:0] MAX_VAL =
        (1 <<< (DATA_WIDTH-1)) - 1;

    localparam signed [ACC_WIDTH-1:0] MIN_VAL =
        -(1 <<< (DATA_WIDTH-1));

    // Generate parallel quantization units
    genvar i;

    generate
        for (i = 0; i < FEATURE_DIM; i = i + 1) begin : quant_units

            wire signed [ACC_WIDTH-1:0] feature;

            wire signed [ACC_WIDTH-1:0] scaled;

            wire signed [DATA_WIDTH-1:0] quantized;

            // Extract INT32 feature
            assign feature =
                data_in[i*ACC_WIDTH +: ACC_WIDTH];

            // Perform arithmetic right shift
            assign scaled = feature >>> shift;

            // Apply signed saturation
            assign quantized =
                (scaled > MAX_VAL)
                ? MAX_VAL[DATA_WIDTH-1:0]
                : (scaled < MIN_VAL)
                ? MIN_VAL[DATA_WIDTH-1:0]
                : scaled[DATA_WIDTH-1:0];

            // Connect quantized output
            assign data_out[i*DATA_WIDTH +: DATA_WIDTH] =
                quantized;

        end
    endgenerate

endmodule
