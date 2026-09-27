// ============================================================
// fifo_assertions.sv
//
// SystemVerilog Assertions (SVA) checker for sync_fifo.
// Kept completely separate from the RTL file and attached from
// the outside using `bind`, so the DUT source (sync_fifo.v) is
// never touched. This lets the same checker be reused with any
// testbench (UVM or otherwise) that instantiates sync_fifo.
// ============================================================

module fifo_checker (
    input logic clk,
    input logic rst_n,
    input logic wr_en,
    input logic rd_en,
    input logic full,
    input logic empty
);

    // Rule 1: full and empty can never both be true at the same time.
    property no_full_and_empty;
        @(posedge clk) disable iff (!rst_n)
        !(full && empty);
    endproperty
    assert property (no_full_and_empty)
    else $error("VIOLATION: full and empty are both high at the same time!");

    // Rule 2: a write attempt while full must not corrupt state.
    // If wr_en && full this cycle, then full must still be the same
    // value one cycle later (i.e. nothing was actually written in).
    property no_write_when_full;
        @(posedge clk) disable iff (!rst_n)
        (wr_en && full) |=> $stable(full);
    endproperty
    assert property (no_write_when_full)
    else $error("VIOLATION: write accepted while FIFO was full!");

    // Rule 3: a read attempt while empty must not corrupt state.
    property no_read_when_empty;
        @(posedge clk) disable iff (!rst_n)
        (rd_en && empty) |=> $stable(empty);
    endproperty
    assert property (no_read_when_empty)
    else $error("VIOLATION: read accepted while FIFO was empty!");

endmodule

// Attach fifo_checker to every instance of sync_fifo, wiring up
// the signals it needs to observe. No changes to sync_fifo.v itself.
bind sync_fifo fifo_checker checker_inst (
    .clk    (clk),
    .rst_n  (rst_n),
    .wr_en  (wr_en),
    .rd_en  (rd_en),
    .full   (full),
    .empty  (empty)
);
