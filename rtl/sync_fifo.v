// sync_fifo.v
// basic synchronous FIFO, DEPTH deep and WIDTH bits wide
// the tricky part here is full/empty detection - using one extra bit
// on the pointers so wr_ptr == rd_ptr doesn't mean two different things

module sync_fifo #(
    parameter DEPTH = 8,
    parameter WIDTH = 8
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             wr_en,
    input  wire [WIDTH-1:0] wr_data,
    input  wire             rd_en,
    output reg  [WIDTH-1:0] rd_data,
    output wire             full,
    output wire             empty
);

    // the actual storage - DEPTH slots, each WIDTH bits
    reg [WIDTH-1:0] mem [0:DEPTH-1];

    // pointers are 1 bit wider than needed just to index the memory
    // that extra top bit is what lets us tell full apart from empty
    reg [$clog2(DEPTH):0] wr_ptr;
    reg [$clog2(DEPTH):0] rd_ptr;

    // write side - only actually writes if we're not full
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
        end else if (wr_en && !full) begin
            mem[wr_ptr[$clog2(DEPTH)-1:0]] <= wr_data;
            wr_ptr <= wr_ptr + 1;
        end
        // if wr_en is high but full is also high, we just do nothing
        // (this is the overflow guard, checked later with assertions too)
    end

    // read side - same idea but for reading
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 0;
        end else if (rd_en && !empty) begin
            rd_data <= mem[rd_ptr[$clog2(DEPTH)-1:0]];
            rd_ptr <= rd_ptr + 1;
        end
    end

    // empty: pointers match completely, including the extra bit
    // full: the index bits match but the extra bit doesn't -
    // means write pointer has lapped the read pointer exactly once
    assign empty = (wr_ptr == rd_ptr);
    assign full  = (wr_ptr[$clog2(DEPTH)-1:0] == rd_ptr[$clog2(DEPTH)-1:0]) &&
                   (wr_ptr[$clog2(DEPTH)]     != rd_ptr[$clog2(DEPTH)]);

endmodule