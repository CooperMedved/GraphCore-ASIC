
module mac_array #(
    parameter ARRAY_SIZE = 4,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32
)(
    input wire clk,
    input wire rst,
    input wire en,
    input wire clear,

    input wire [(ARRAY_SIZE*DATA_WIDTH)-1:0] a_in,
    input wire [(ARRAY_SIZE*DATA_WIDTH)-1:0] b_in,

    output wire [(ARRAY_SIZE*ARRAY_SIZE*ACC_WIDTH)-1:0] c_out
);

    // Internal horizontal connections
    wire signed [DATA_WIDTH-1:0] a_bus
        [0:ARRAY_SIZE-1][0:ARRAY_SIZE];

    // Internal vertical connections
    wire signed [DATA_WIDTH-1:0] b_bus
        [0:ARRAY_SIZE][0:ARRAY_SIZE-1];

    // Connect external inputs to array boundaries
    genvar i;

    generate
        for (i = 0; i < ARRAY_SIZE; i = i + 1)
        begin : input_connections

            assign a_bus[i][0] =
                a_in[i*DATA_WIDTH +: DATA_WIDTH];

            assign b_bus[0][i] =
                b_in[i*DATA_WIDTH +: DATA_WIDTH];

        end
    endgenerate

    // Generate the systolic array
    genvar r, c;

    generate
        for (r = 0; r < ARRAY_SIZE; r = r + 1)
        begin : rows

            for (c = 0; c < ARRAY_SIZE; c = c + 1)
            begin : cols

                processing_element #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH(ACC_WIDTH)
                ) pe_inst (
                    .clk(clk),
                    .rst(rst),
                    .en(en),
                    .clear(clear),

                    .a_in(a_bus[r][c]),
                    .b_in(b_bus[r][c]),

                    .a_out(a_bus[r][c+1]),
                    .b_out(b_bus[r+1][c]),

                    .acc_out(
                        c_out[(r*ARRAY_SIZE+c)*ACC_WIDTH
                              +: ACC_WIDTH]
                    )
                );

            end
        end
    endgenerate

endmodule
