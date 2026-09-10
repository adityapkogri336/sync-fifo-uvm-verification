module sync_fifo #(
    parameter DEPTH = 8,      // number of slots
    parameter WIDTH = 8       // bits per slot
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

    // Internal storage: DEPTH slots, each WIDTH bits wide
    reg [WIDTH-1:0] mem [0:DEPTH-1];

    // Pointers: extra bit for wrap tracking
    reg [$clog2(DEPTH):0] wr_ptr;
    reg [$clog2(DEPTH):0] rd_ptr;

    // Write logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
        end else if (wr_en && !full) begin
            mem[wr_ptr[$clog2(DEPTH)-1:0]] <= wr_data;
            wr_ptr <= wr_ptr + 1;
        end
    end

    // Read logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 0;
        end else if (rd_en && !empty) begin
            rd_data <= mem[rd_ptr[$clog2(DEPTH)-1:0]];
            rd_ptr <= rd_ptr + 1;
        end
    end

    // Full/empty logic — combinational, derived from pointer comparison
    assign empty = (wr_ptr == rd_ptr);
    assign full  = (wr_ptr[$clog2(DEPTH)-1:0] == rd_ptr[$clog2(DEPTH)-1:0]) &&
                   (wr_ptr[$clog2(DEPTH)] != rd_ptr[$clog2(DEPTH)]);

endmodule
