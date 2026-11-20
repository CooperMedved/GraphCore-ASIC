module weight_memory #(
    parameter INPUT_DIM  = 16,
    parameter OUTPUT_DIM = 8,
    parameter ARRAY_SIZE = 4,
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 5
)(
    input wire clk,

    // Weight loading interface
    input wire we,
    input wire [ADDR_WIDTH-1:0] wr_addr,
    input wire [(ARRAY_SIZE*DATA_WIDTH)-1:0] wr_data,

    // Weight read interface
    input wire [ADDR_WIDTH-1:0] rd_addr,
    output wire [(ARRAY_SIZE*DATA_WIDTH)-1:0] rd_data
);

    // Local parameters
    localparam NUM_TILES = OUTPUT_DIM / ARRAY_SIZE;
    localparam MEM_DEPTH = INPUT_DIM * NUM_TILES;
    localparam WORD_WIDTH = ARRAY_SIZE * DATA_WIDTH;

    // Internal memory array
    reg [WORD_WIDTH-1:0] memory [0:MEM_DEPTH-1];

    // Synchronous write logic
    always @(posedge clk) begin
        if(we && wr_addr < MEM_DEPTH) begin
            memory[wr_addr] <= wr_data;
        end
    end

    // Asynchronous read logic
    assign rd_data = (rd_addr < MEM_DEPTH)
               ? memory[rd_addr]
               : {WORD_WIDTH{1'b0}};
endmodule