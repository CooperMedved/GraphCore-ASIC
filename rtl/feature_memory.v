module feature_memory #(
    parameter MAX_NODES  = 64,
    parameter NODE_WIDTH = 6,
    parameter FEATURE_DIM = 8,
    parameter DATA_WIDTH = 8
)(
    input wire clk,

    // Write interface
    input wire we,
    input wire [NODE_WIDTH-1:0] wr_addr,
    input wire [(FEATURE_DIM*DATA_WIDTH)-1:0] wr_data,

    // Read interface
    input wire [NODE_WIDTH-1:0] rd_addr,
    output wire [(FEATURE_DIM*DATA_WIDTH)-1:0] rd_data
);

    // Internal memory array
    localparam VECTOR_WIDTH = FEATURE_DIM * DATA_WIDTH;

    reg [VECTOR_WIDTH-1:0] memory [0:MAX_NODES-1];

    // Synchronous write logic

    always @(posedge clk) begin
        if(we && wr_addr < MAX_NODES) begin
            memory[wr_addr] <= wr_data;
        end
    end
    

    // Asynchronous read logic
   assign rd_data = (rd_addr < MAX_NODES)
               ? memory[rd_addr]
               : {VECTOR_WIDTH{1'b0}};

endmodule