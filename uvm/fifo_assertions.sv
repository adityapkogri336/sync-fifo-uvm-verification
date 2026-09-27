// fifo_assertions.sv
// checks the FIFO's own rules on every clock cycle, independent of any test.
// kept out of sync_fifo.v on purpose and attached from outside with bind,
// so the RTL file stays untouched and this can be reused with any testbench

module fifo_checker (
    input logic clk,
    input logic rst_n,
    input logic wr_en,
    input logic rd_en,
    input logic full,
    input logic empty
);

    // full and empty should never both be true at once
    property no_full_and_empty;
        @(posedge clk) disable iff (!rst_n)
        !(full && empty);
    endproperty
    assert property (no_full_and_empty)
    else $error("VIOLATION: full and empty are both high at the same time!");

    // if we try to write while full, full should still be the same
    // value one cycle later - i.e. nothing actually got written
    // (checking next cycle here, not this one, since the pointer update
    // from this edge doesn't show up until the next edge anyway)
    property no_write_when_full;
        @(posedge clk) disable iff (!rst_n)
        (wr_en && full) |=> $stable(full);
    endproperty
    assert property (no_write_when_full)
    else $error("VIOLATION: write accepted while FIFO was full!");

    // same idea for reading from an empty FIFO
    property no_read_when_empty;
        @(posedge clk) disable iff (!rst_n)
        (rd_en && empty) |=> $stable(empty);
    endproperty
    assert property (no_read_when_empty)
    else $error("VIOLATION: read accepted while FIFO was empty!");

endmodule

// attach the checker to every instance of sync_fifo - no edits to sync_fifo.v needed
bind sync_fifo fifo_checker checker_inst (
    .clk    (clk),
    .rst_n  (rst_n),
    .wr_en  (wr_en),
    .rd_en  (rd_en),
    .full   (full),
    .empty  (empty)
);