interface fifo_if (input logic clk);
    logic rst_n;
    logic wr_en;
    logic [7:0] wr_data;
    logic rd_en;
    logic [7:0] rd_data;
    logic full;
    logic empty;
endinterface
