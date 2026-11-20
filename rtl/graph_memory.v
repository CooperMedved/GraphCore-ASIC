
module graph_memory #(
    parameter MAX_NODES  = 64,
    parameter MAX_EDGES  = 256,
    parameter NODE_WIDTH = 6,
    parameter EDGE_WIDTH = 9
)(
    input wire clk,

    // Row pointer write interface
    input wire row_we,
    input wire [NODE_WIDTH:0] row_wr_addr,
    input wire [EDGE_WIDTH-1:0] row_wr_data,

    // Column index write interface
    input wire col_we,
    input wire [EDGE_WIDTH-1:0] col_wr_addr,
    input wire [NODE_WIDTH-1:0] col_wr_data,

    // Row pointer read interface
    input wire [NODE_WIDTH:0] row_addr,
    output wire [EDGE_WIDTH-1:0] row_data,

    // Column index read interface
    input wire [EDGE_WIDTH-1:0] col_addr,
    output wire [NODE_WIDTH-1:0] col_data
);

    // Internal memory arrays
    reg [EDGE_WIDTH-1:0] row_ptr [0:MAX_NODES];

    reg [NODE_WIDTH-1:0] col_idx [0:MAX_EDGES-1];

    // Synchronous write logic
    always @(posedge clk) begin

        // Write row pointer memory
        if (row_we && row_wr_addr <= MAX_NODES) begin
            row_ptr[row_wr_addr] <= row_wr_data;
        end

        // Write column index memory
        if (col_we && col_wr_addr < MAX_EDGES) begin
            col_idx[col_wr_addr] <= col_wr_data;
        end

    end

    // Asynchronous row pointer read
    assign row_data = (row_addr <= MAX_NODES)
                    ? row_ptr[row_addr]
                    : {EDGE_WIDTH{1'b0}};

    // Asynchronous column index read
    assign col_data = (col_addr < MAX_EDGES)
                    ? col_idx[col_addr]
                    : {NODE_WIDTH{1'b0}};

endmodule
