// tb_sync_fifo.sv
// plain directed testbench, no UVM here, just checking the FIFO does what it should
// basic idea: write some known values in, read them back, make sure they match
// then hammer it a bit with overflow/underflow to make sure it doesn't break

module tb;

    logic clk;
    logic rst_n;
    logic wr_en;
    logic [7:0] wr_data;
    logic rd_en;
    logic [7:0] rd_data;
    logic full;
    logic empty;

    // hook up the FIFO we're testing (DUT)
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

    // clock - toggles every 5 units so full period is 10
    initial clk = 0;
    always #5 clk = ~clk;

    // keeping the values we write so we can check them later during overflow test
    logic [7:0] expected_values [0:7];

    // writes one value in - drive it for one clock then drop wr_en
    task write_data(input [7:0] data);
        @(posedge clk);
        wr_en   = 1;
        wr_data = data;
        @(posedge clk);
        wr_en   = 0;
    endtask

    // reads one value and checks it against what we expect
    // the #1 here matters - without it we'd read rd_data before it actually updates
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

    // fill it all the way up, try to sneak one more write in (should be ignored),
    // then drain it and check nothing got messed up
    task test_overflow();
        $display("--- Starting overflow test ---");

        for (int i = 0; i < 8; i++) begin
            write_data(expected_values[i]);
        end

        if (full !== 1)
            $display("FAIL: expected full=1 after 8 writes, got full=%b", full);
        else
            $display("PASS: full correctly asserted after 8 writes");

        // this write should just get dropped since we're full
        write_data(8'h99);

        for (int i = 0; i < 8; i++) begin
            read_and_check(expected_values[i]);
        end

        $display("--- Overflow test complete ---");
    endtask

    // try to read from an empty FIFO - shouldn't do anything weird
    task test_underflow();
        $display("--- Starting underflow test ---");

        if (empty !== 1)
            $display("FAIL: expected empty=1, got empty=%b", empty);
        else
            $display("PASS: empty correctly asserted");

        // phantom read - rd_data should just stay whatever it was
        @(posedge clk);
        rd_en = 1;
        @(posedge clk);
        rd_en = 0;
        #1;
        $display("Note: rd_data after phantom read = %h (should be unchanged from last real read)", rd_data);

        $display("--- Underflow test complete ---");
    endtask

    initial begin
        rst_n   = 0;
        wr_en   = 0;
        rd_en   = 0;
        wr_data = 0;

        // values we'll use for the overflow test later
        expected_values[0] = 8'h01;
        expected_values[1] = 8'h02;
        expected_values[2] = 8'h03;
        expected_values[3] = 8'h04;
        expected_values[4] = 8'h05;
        expected_values[5] = 8'h06;
        expected_values[6] = 8'h07;
        expected_values[7] = 8'h08;

        #12;
        rst_n = 1;
        #10;

        // basic sanity check first - write 3, read 3, order should hold
        write_data(8'hAA);
        write_data(8'hBB);
        write_data(8'hCC);

        read_and_check(8'hAA);
        read_and_check(8'hBB);
        read_and_check(8'hCC);

        // now the corner cases
        test_overflow();
        test_underflow();

        #20;
        $display("Testbench complete.");
        $finish;
    end

endmodule