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

    // Array to hold values we write, so we can check them later
    logic [7:0] expected_values [0:7];

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

    // Test: fill the FIFO completely, attempt one extra "phantom" write,
    // then drain and confirm no data was corrupted (overflow protection)
    task test_overflow();
        $display("--- Starting overflow test ---");

        for (int i = 0; i < 8; i++) begin
            write_data(expected_values[i]);
        end

        if (full !== 1)
            $display("FAIL: expected full=1 after 8 writes, got full=%b", full);
        else
            $display("PASS: full correctly asserted after 8 writes");

        // Attempt a 9th "phantom" write — should be ignored
        write_data(8'h99);

        // Drain all 8 real values and confirm none were corrupted
        for (int i = 0; i < 8; i++) begin
            read_and_check(expected_values[i]);
        end

        $display("--- Overflow test complete ---");
    endtask

    // Test: attempt to read from an already-empty FIFO (underflow protection)
    task test_underflow();
        $display("--- Starting underflow test ---");

        if (empty !== 1)
            $display("FAIL: expected empty=1, got empty=%b", empty);
        else
            $display("PASS: empty correctly asserted");

        // Attempt a "phantom" read — should be ignored, rd_data should hold last value
        @(posedge clk);
        rd_en = 1;
        @(posedge clk);
        rd_en = 0;
        #1;
        $display("Note: rd_data after phantom read = %h (should be unchanged from last real read)", rd_data);

        $display("--- Underflow test complete ---");
    endtask

    initial begin
        // Initialize all inputs to known values
        rst_n   = 0;
        wr_en   = 0;
        rd_en   = 0;
        wr_data = 0;

        // Set up expected values for the overflow/underflow tests
        expected_values[0] = 8'h01;
        expected_values[1] = 8'h02;
        expected_values[2] = 8'h03;
        expected_values[3] = 8'h04;
        expected_values[4] = 8'h05;
        expected_values[5] = 8'h06;
        expected_values[6] = 8'h07;
        expected_values[7] = 8'h08;

        // Hold reset for a couple clock cycles
        #12;
        rst_n = 1;

        // Wait for a real clock edge before starting normal operation
        #10;

        // --- Basic directed test: write 3, read 3, check order ---
        write_data(8'hAA);
        write_data(8'hBB);
        write_data(8'hCC);

        read_and_check(8'hAA);
        read_and_check(8'hBB);
        read_and_check(8'hCC);

        // --- Corner case tests ---
        test_overflow();
        test_underflow();

        #20;
        $display("Testbench complete.");
        $finish;
    end

endmodule