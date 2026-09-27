package fifo_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // ---------------- Transaction ----------------
    class fifo_transaction extends uvm_sequence_item;
        rand bit [7:0] data;
        rand bit is_write;   // 1 = write operation, 0 = read operation

        // Weight writes more heavily (60%) so reads usually have something to consume
        constraint is_write_dist {
            is_write dist { 1 := 60, 0 := 40 };
        }

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

    // ---------------- Random Mixed Sequence ----------------
    class fifo_random_sequence extends uvm_sequence #(fifo_transaction);
        `uvm_object_utils(fifo_random_sequence)

        function new(string name = "fifo_random_sequence");
            super.new(name);
        endfunction

        task body();
            fifo_transaction tr;
            repeat (20) begin
                tr = fifo_transaction::type_id::create("tr");
                start_item(tr);
                assert(tr.randomize());   // randomizes BOTH data and is_write now
                finish_item(tr);
            end
        endtask
    endclass

    // ---------------- Fill Sequence (forces full=1, closing the coverage hole) ----------------
    class fifo_fill_sequence extends uvm_sequence #(fifo_transaction);
        `uvm_object_utils(fifo_fill_sequence)

        function new(string name = "fifo_fill_sequence");
            super.new(name);
        endfunction

        task body();
            fifo_transaction tr;
            // DEPTH writes back-to-back, no reads in between, guarantees full=1 at least once
            repeat (8) begin
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

    // ---------------- Coverage Collector ----------------
    class fifo_coverage extends uvm_component;
        `uvm_component_utils(fifo_coverage)

        virtual fifo_if vif;

        covergroup cg;
            option.per_instance = 1;
            cp_wr_en: coverpoint vif.wr_en;
            cp_rd_en: coverpoint vif.rd_en;
            cp_full:  coverpoint vif.full;
            cp_empty: coverpoint vif.empty;
            cross_full_wr:  cross cp_full, cp_wr_en;
            cross_empty_rd: cross cp_empty, cp_rd_en;
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            cg = new();
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "Virtual interface not found for coverage")
        endfunction

        task run_phase(uvm_phase phase);
            @(posedge vif.rst_n);
            forever begin
                @(posedge vif.clk);
                #1;
                cg.sample();
            end
        endtask

        function void report_phase(uvm_phase phase);
            `uvm_info("COVERAGE", $sformatf("Overall functional coverage: %0.2f%%", cg.get_coverage()), UVM_LOW)
            `uvm_info("COVERAGE", $sformatf("  cp_wr_en        : %0.2f%%", cg.cp_wr_en.get_coverage()), UVM_LOW)
            `uvm_info("COVERAGE", $sformatf("  cp_rd_en        : %0.2f%%", cg.cp_rd_en.get_coverage()), UVM_LOW)
            `uvm_info("COVERAGE", $sformatf("  cp_full         : %0.2f%%", cg.cp_full.get_coverage()), UVM_LOW)
            `uvm_info("COVERAGE", $sformatf("  cp_empty        : %0.2f%%", cg.cp_empty.get_coverage()), UVM_LOW)
            `uvm_info("COVERAGE", $sformatf("  cross_full_wr   : %0.2f%%", cg.cross_full_wr.get_coverage()), UVM_LOW)
            `uvm_info("COVERAGE", $sformatf("  cross_empty_rd  : %0.2f%%", cg.cross_empty_rd.get_coverage()), UVM_LOW)
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
        fifo_coverage   cov;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agt = fifo_agent::type_id::create("agt", this);
            sb  = fifo_scoreboard::type_id::create("sb", this);
            cov = fifo_coverage::type_id::create("cov", this);
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
            fifo_write_sequence  wr_seq;
            fifo_read_sequence   rd_seq;
            fifo_random_sequence rand_seq;
            fifo_fill_sequence   fill_seq;
            phase.raise_objection(this);

            wr_seq = fifo_write_sequence::type_id::create("wr_seq");
            wr_seq.start(env.agt.seqr);

            rd_seq = fifo_read_sequence::type_id::create("rd_seq");
            rd_seq.start(env.agt.seqr);

            rand_seq = fifo_random_sequence::type_id::create("rand_seq");
            rand_seq.start(env.agt.seqr);

            // Directed: deliberately force full=1, since random alone didn't reach it
            fill_seq = fifo_fill_sequence::type_id::create("fill_seq");
            fill_seq.start(env.agt.seqr);

            #100;   // give the monitor time to observe the final transaction before ending
            phase.drop_objection(this);
        endtask
    endclass

endpackage