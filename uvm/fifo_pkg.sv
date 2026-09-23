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

    // ---------------- Sequence ----------------
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
            forever begin
                seq_item_port.get_next_item(tr);
                @(posedge vif.clk);
                if (tr.is_write) begin
                    vif.wr_en   = 1;
                    vif.wr_data = tr.data;
                end else begin
                    vif.rd_en = 1;
                end
                @(posedge vif.clk);
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
            forever begin
                @(posedge vif.clk);
                if (vif.wr_en && !vif.full) begin
                    tr = fifo_transaction::type_id::create("tr");
                    tr.is_write = 1;
                    tr.data     = vif.wr_data;
                    ap.write(tr);
                end
                if (vif.rd_en && !vif.empty) begin
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
            fifo_write_sequence seq;
            phase.raise_objection(this);
            seq = fifo_write_sequence::type_id::create("seq");
            seq.start(env.agt.seqr);
            phase.drop_objection(this);
        endtask
    endclass

endpackage
