// tb_top.sv
// top level - wires the DUT to the interface, makes the clock, handles reset,
// and kicks off UVM. the three initial blocks below are split up on purpose -
// run_test has to start at time 0, so nothing that eats sim time can be in
// the same block as it (learned that one the hard way)

`include "fifo_if.sv"
`include "fifo_assertions.sv"
`include "fifo_pkg.sv"
`include "uvm_macros.svh"
import uvm_pkg::*;
import fifo_pkg::*;

module tb_top;
    logic clk;

    // interface carries the clock in, everything else gets driven through it
    fifo_if vif(clk);

    // the actual FIFO, wired up to the interface signals instead of raw wires
    sync_fifo #(.DEPTH(8), .WIDTH(8)) dut (
        .clk(clk),
        .rst_n(vif.rst_n),
        .wr_en(vif.wr_en),
        .wr_data(vif.wr_data),
        .rd_en(vif.rd_en),
        .rd_data(vif.rd_data),
        .full(vif.full),
        .empty(vif.empty)
    );

    // clock - 10 unit period
    initial clk = 0;
    always #5 clk = ~clk;

    // publish the vif so any UVM component can grab it with config_db::get
    initial begin
        uvm_config_db#(virtual fifo_if)::set(null, "*", "vif", vif);
    end

    // reset pulse, runs on its own so it doesn't block run_test from starting at time 0
    initial begin
        vif.rst_n = 0;
        #12;
        vif.rst_n = 1;
    end

    // this has to be the only thing happening before run_test, no delays allowed here
    initial begin
        run_test("fifo_test");
    end
endmodule