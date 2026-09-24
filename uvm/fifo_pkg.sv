package fifo_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // ---------------- Transaction ----------------
    class fifo_transaction extends uvm_sequence_item;
        rand bit [7:0] data;
        bit is_write;   // 1 = write operation, 0 = read operation

        `uvm_object_utils(fifo_transaction)

        function new(string name = "fifo_transaction");
            super.new(name);
        endfunction
    endclass

    // ---------------- Write Sequence ----------------
    class fifo_write_sequence extends uvm_sequence #(fifo_transaction);
        `uvm_object_utils(fifo_write_sequence)

        function new(string name = "fifo_write_sequence");
            super.new(name);
        endfunction

        task body();
            fifo_transaction tr;
            repeat (3) begin
                tr = fifo_transaction::type_id::create("tr");
                start_item(tr);
                assert(tr.randomize());
                tr.is_write = 1;
                finish_item(tr);
            end
        endtask
    endclass

    // ---------------- Read Sequence ----------------
    class fifo_read_sequence extends uvm_sequence #(fifo_transaction);
        `uvm_object_utils(fifo_read_sequence)

        function new(string name = "fifo_read_sequence");
            super.new(name);
        endfunction

        task body();
            fifo_transaction tr;
            repeat (3) begin
                tr = fifo_transaction::type_id::create("tr");
                start_item(tr);
                tr.is_write = 0;   // no randomize() needed — data field is irrelevant for a read request
                finish_item(tr);
            end
        endtask
    endclass

    // ---------------- Driver ----------------
    class fifo_driver extends uvm_driver #(fifo_transaction);
        `uvm_component_utils(fifo_driver)

        virtual fifo_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "Virtual interface not found for driver")
        endfunction

        task run_phase(uvm_phase phase);
            fifo_transaction tr;
            @(posedge vif.rst_n);   // wait until reset is fully released
            @(posedge vif.clk);     // let one clean clock edge pass before driving anything
            forever begin
                seq_item_port.get_next_item(tr);
                @(posedge vif.clk);
                #1;   // avoid racing with the DUT, which samples wr_en/rd_en on this same edge
                if (tr.is_write) begin
                    vif.wr_en   = 1;
                    vif.wr_data = tr.data;
                end else begin
                    vif.rd_en = 1;
                end
                @(posedge vif.clk);
                #1;
                vif.wr_en = 0;
                vif.rd_en = 0;
                seq_item_port.item_done();
            end
        endtask
    endclass

    // ---------------- Monitor ----------------
    class fifo_monitor extends uvm_monitor;
        `uvm_component_utils(fifo_monitor)

        virtual fifo_if vif;
        uvm_analysis_port #(fifo_transaction) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "Virtual interface not found for monitor")
        endfunction

        task run_phase(uvm_phase phase);
            fifo_transaction tr;
            bit wr_en_s, rd_en_s, full_s, empty_s;
            @(posedge vif.rst_n);   // don't observe anything until reset is fully released
            forever begin
                @(posedge vif.clk);
                // Capture control/status signals exactly as the DUT saw them for THIS edge,
                // before this same edge's own pointer updates can change full/empty.
                wr_en_s = vif.wr_en;
                rd_en_s = vif.rd_en;
                full_s  = vif.full;
                empty_s = vif.empty;
                #1;   // now let data outputs (rd_data) settle
                if (wr_en_s && !full_s) begin
                    tr = fifo_transaction::type_id::create("tr");
                    tr.is_write = 1;
                    tr.data     = vif.wr_data;
                    ap.write(tr);
                end
                if (rd_en_s && !empty_s) begin
                    tr = fifo_transaction::type_id::create("tr");
                    tr.is_write = 0;
                    tr.data     = vif.rd_data;
                    ap.write(tr);
                end
            end
        endtask
    endclass

    // ---------------- Scoreboard ----------------
    class fifo_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(fifo_scoreboard)

        uvm_analysis_imp #(fifo_transaction, fifo_scoreboard) ap_imp;
        bit [7:0] expected_queue[$];

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap_imp = new("ap_imp", this);
        endfunction

        function void write(fifo_transaction tr);
            if (tr.is_write) begin
                expected_queue.push_back(tr.data);
                `uvm_info("SCOREBOARD", $sformatf("Write observed: %0h", tr.data), UVM_LOW)
            end else begin
                bit [7:0] expected_data;
                if (expected_queue.size() == 0) begin
                    `uvm_error("SCOREBOARD", "Read observed but expected queue is empty!")
                    return;
                end
                expected_data = expected_queue.pop_front();
                if (tr.data !== expected_data)
                    `uvm_error("SCOREBOARD", $sformatf("MISMATCH: expected %0h, got %0h", expected_data, tr.data))
                else
                    `uvm_info("SCOREBOARD", $sformatf("PASS: got %0h as expected", tr.data), UVM_LOW)
            end
        endfunction
    endclass

    // ---------------- Agent ----------------
    class fifo_agent extends uvm_agent;
        `uvm_component_utils(fifo_agent)

        fifo_driver  drv;
        fifo_monitor mon;
        uvm_sequencer #(fifo_transaction) seqr;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            drv  = fifo_driver::type_id::create("drv", this);
            mon  = fifo_monitor::type_id::create("mon", this);
            seqr = uvm_sequencer#(fifo_transaction)::type_id::create("seqr", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            drv.seq_item_port.connect(seqr.seq_item_export);
        endfunction
    endclass

    // ---------------- Environment ----------------
    class fifo_env extends uvm_env;
        `uvm_component_utils(fifo_env)

        fifo_agent      agt;
        fifo_scoreboard sb;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agt = fifo_agent::type_id::create("agt", this);
            sb  = fifo_scoreboard::type_id::create("sb", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            agt.mon.ap.connect(sb.ap_imp);
        endfunction
    endclass

    // ---------------- Test ----------------
    class fifo_test extends uvm_test;
        `uvm_component_utils(fifo_test)

        fifo_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = fifo_env::type_id::create("env", this);
        endfunction

        task run_phase(uvm_phase phase);
            fifo_write_sequence wr_seq;
            fifo_read_sequence  rd_seq;
            phase.raise_objection(this);

            wr_seq = fifo_write_sequence::type_id::create("wr_seq");
            wr_seq.start(env.agt.seqr);

            rd_seq = fifo_read_sequence::type_id::create("rd_seq");
            rd_seq.start(env.agt.seqr);

            #100;   // give the monitor time to observe the final transaction before ending
            phase.drop_objection(this);
        endtask
    endclass

endpackage