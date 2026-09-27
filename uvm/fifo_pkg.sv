// fifo_pkg.sv
// all the UVM classes live here - transaction, sequences, driver, monitor,
// scoreboard, coverage, and the agent/env/test that glue it together

package fifo_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // ---------------- Transaction ----------------
    // one object = one thing we want the DUT to do (a write or a read)
    class fifo_transaction extends uvm_sequence_item;
        rand bit [7:0] data;
        rand bit is_write;   // 1 = write, 0 = read

        // weighting writes higher so the FIFO usually has something in it
        // when a read comes along, otherwise reads mostly hit an empty FIFO
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
                tr.is_write = 0;   // data field doesn't matter for a read request
                finish_item(tr);
            end
        endtask
    endclass

    // ---------------- Random Mixed Sequence ----------------
    // fully random - lets both data and is_write get picked by the solver
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
                assert(tr.randomize());
                finish_item(tr);
            end
        endtask
    endclass

    // ---------------- Fill Sequence ----------------
    // added this after noticing random testing never actually filled the FIFO -
    // this just hammers 8 writes back to back with no reads so full=1 is guaranteed
    class fifo_fill_sequence extends uvm_sequence #(fifo_transaction);
        `uvm_object_utils(fifo_fill_sequence)

        function new(string name = "fifo_fill_sequence");
            super.new(name);
        endfunction

        task body();
            fifo_transaction tr;
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
    // takes whatever transaction the sequencer hands it and actually
    // wiggles the DUT pins to make it happen
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

            // don't touch anything until reset is actually done
            @(posedge vif.rst_n);
            @(posedge vif.clk);

            forever begin
                seq_item_port.get_next_item(tr);

                // the #1 here avoids racing the DUT, which samples wr_en/rd_en
                // on this exact same edge
                @(posedge vif.clk);
                #1;
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
    // just watches the bus, never drives anything - rebuilds transactions
    // for the scoreboard and coverage to use
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

            @(posedge vif.rst_n);

            forever begin
                @(posedge vif.clk);

                // grab the status flags right at the edge, before this same
                // edge's own pointer update can change them out from under us
                // (this was the bug that dropped the last read in a drain -
                // empty flips to 1 on the exact same edge as the read that causes it)
                wr_en_s = vif.wr_en;
                rd_en_s = vif.rd_en;
                full_s  = vif.full;
                empty_s = vif.empty;

                #1;   // now the data outputs have settled, safe to read them

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
    // keeps our own queue of what we expect to come out, compares every read
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

    // ---------------- Coverage ----------------
    // measures whether we actually hit every state that matters, not just
    // that stuff ran - the crosses are the important part (full+write, empty+read)
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
    // just bundles driver + monitor + sequencer and wires them together
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
    // bundles agent + scoreboard + coverage
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
    // decides which sequences actually run and in what order
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

            // directed on purpose - random alone kept missing full=1
            fill_seq = fifo_fill_sequence::type_id::create("fill_seq");
            fill_seq.start(env.agt.seqr);

            #100;   // give the monitor time to catch the last transaction
            phase.drop_objection(this);
        endtask
    endclass

endpackage