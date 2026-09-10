module tb;

    // Testbench signals — these will drive/observe the DUT's ports
    logic clk;
    logic rst_n;
    logic wr_en;
    logic [7:0] wr_data;
    logic rd_en;
    logic [7:0] rd_data;
    logic full;
    logic empty;

    // Instantiate the FIFO design (DUT = Design Under Test)
    sync_fifo #(.DEPTH(8), .WIDTH(8)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .rd_en(rd_en),
        .rd_data(rd_data),
        .full(full),
        .empty(empty)
    );

    // Clock generation: toggle every 5 time units -> 10 time unit period
    initial clk = 0;
    always #5 clk = ~clk;

    // Task: write one value into the FIFO
    task write_data(input [7:0] data);
        @(posedge clk);
        wr_en   = 1;
        wr_data = data;
        @(posedge clk);
        wr_en   = 0;
    endtask

    // Task: read one value and self-check against an expected value
    task read_and_check(input [7:0] expected);
        @(posedge clk);
        rd_en = 1;
        @(posedge clk);
        rd_en = 0;
        #1;
        if (rd_data !== expected)
            $display("FAIL at time %0t: expected %h, got %h", $time, expected, rd_data);
        else
            $display("PASS at time %0t: got %h as expected", $time, rd_data);
    endtask

    initial begin
        // Initialize all inputs to known values
        rst_n   = 0;
        wr_en   = 0;
        rd_en   = 0;
        wr_data = 0;

        // Hold reset for a couple clock cycles
        #12;
        rst_n = 1;

        // Wait for a real clock edge before starting normal operation
        #10;

        // Write 3 values in
        write_data(8'hAA);
        write_data(8'hBB);
        write_data(8'hCC);

        // Read them back and check they come out in the same order (FIFO order)
        read_and_check(8'hAA);
        read_and_check(8'hBB);
        read_and_check(8'hCC);

        #20;
        $display("Testbench complete.");
        $finish;
    end

endmodule
