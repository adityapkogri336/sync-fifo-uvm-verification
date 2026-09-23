`include "fifo_if.sv"
`include "fifo_pkg.sv"
`include "uvm_macros.svh"
import uvm_pkg::*;
import fifo_pkg::*;

module tb_top;
    logic clk;

    // Instantiate the interface, sharing the clock into it
    fifo_if vif(clk);

    // Instantiate the actual DUT, connecting its ports to the interface's signals
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

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    // Make the interface available to any UVM component that asks for it
    initial begin
        uvm_config_db#(virtual fifo_if)::set(null, "*", "vif", vif);
    end

    // Basic reset sequence — runs in parallel, does NOT delay run_test below
    initial begin
        vif.rst_n = 0;
        #12;
        vif.rst_n = 1;
    end

    // Hand control over to UVM — must start at time 0, so this block has
    // nothing before it that could consume simulation time
    initial begin
        run_test("fifo_test");
    end
endmodule