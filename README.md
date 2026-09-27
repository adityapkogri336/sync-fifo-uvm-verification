# Synchronous FIFO — UVM Verification Project

A synchronous FIFO designed in Verilog and verified using a full UVM (Universal Verification Methodology) testbench, including directed tests, constrained-random stimulus, functional coverage, and SystemVerilog Assertions (SVA).

## Overview

This project implements an 8-deep, 8-bit-wide synchronous FIFO and builds a complete, reusable verification environment around it — the same architecture used in industry to verify hardware blocks before they go to silicon. The goal was to go beyond "does it work once" and build a verification environment that can catch bugs an ad-hoc test would miss: overflow/underflow corruption, race conditions between the driver and DUT, and structural protocol violations.

## Design Under Test (DUT)

`rtl/sync_fifo.v` — a parameterized synchronous FIFO:
- Configurable `DEPTH` (default 8) and `WIDTH` (default 8)
- Write and read pointers each carry one extra "wrap" bit beyond what's needed to index the memory, which is what makes it possible to distinguish a completely full FIFO from a completely empty one when both pointers land on the same index
- `full` and `empty` are combinationally derived from the two pointers
- Write and read logic are independent synchronous processes gated by `!full` and `!empty` respectively, so overflow/underflow can never corrupt stored data

## Verification Environment

Two testbenches exist side by side, showing two different verification approaches:

### 1. Directed testbench (`tb/tb_sync_fifo.sv`)
A self-checking directed testbench in plain SystemVerilog (no UVM) that writes and reads known values, checks results with `!==`, and explicitly drives the FIFO to full/empty to test the overflow/underflow guards.

### 2. UVM environment (`uvm/`)
A complete, reusable UVM testbench:

| Component | File | Role |
|---|---|---|
| `fifo_if` | `fifo_if.sv` | SystemVerilog interface bundling all DUT signals |
| `fifo_transaction` | `fifo_pkg.sv` | Randomizable transaction: `data` + `is_write`, weighted 60/40 write/read |
| `fifo_write_sequence` / `fifo_read_sequence` | `fifo_pkg.sv` | Directed stimulus |
| `fifo_random_sequence` | `fifo_pkg.sv` | 20 fully-randomized read/write transactions |
| `fifo_fill_sequence` | `fifo_pkg.sv` | Directed sequence that forces the FIFO to `full=1`, closing a coverage gap random testing didn't reach |
| `fifo_driver` | `fifo_pkg.sv` | Drives transactions onto the DUT interface |
| `fifo_monitor` | `fifo_pkg.sv` | Passively observes the interface and reconstructs transactions for the scoreboard/coverage |
| `fifo_scoreboard` | `fifo_pkg.sv` | Self-checking: models expected FIFO contents in a queue, compares every read against it |
| `fifo_coverage` | `fifo_pkg.sv` | Functional coverage: toggle coverage on `wr_en`/`rd_en`/`full`/`empty`, cross coverage on `(full, wr_en)` and `(empty, rd_en)` |
| `fifo_agent` / `fifo_env` / `fifo_test` | `fifo_pkg.sv` | Standard UVM hierarchy tying everything together |
| `fifo_checker` | `fifo_assertions.sv` | SVA protocol checker, attached to the DUT via `bind` (no changes to the RTL file) |

### 3. SystemVerilog Assertions (`uvm/fifo_assertions.sv`)
Three properties, checked on every clock cycle independent of any test sequence:
1. `full` and `empty` can never both be true at the same time
2. A write attempt while `full` must never actually change FIFO state
3. A read attempt while `empty` must never actually change FIFO state

These are bound to the DUT from an external module using `bind`, so the RTL source stays untouched — the checker can be reused with any testbench.

## Verification Methodology

The project follows a standard coverage-driven verification flow:

1. **Directed testing** — hand-written sequences exercise the basic write/read path and explicit overflow/underflow corner cases.
2. **Constrained-random testing** — a weighted-random sequence generates realistic mixed traffic, catching interactions directed tests wouldn't think to write.
3. **Functional coverage** — measures whether random+directed testing actually reached every interesting state, including the dangerous cross of `(full=1, wr_en=1)` and `(empty=1, rd_en=1)`.
4. **Coverage-driven test writing** — random testing alone reached only 83.33% coverage (the FIFO was never actually driven to `full`); a new directed `fifo_fill_sequence` was written specifically to close that gap, reaching 100%.
5. **Assertion-based checking** — independent of the scoreboard, SVA continuously checks that the DUT never violates its own structural contract.

Final result: **100% functional coverage across all coverpoints and crosses, 0 scoreboard errors, 0 assertion violations**, verified on Cadence Xcelium 25.03.

## Bugs Found and Fixed During Verification

Building this environment surfaced four real timing/race-condition bugs, each diagnosed with evidence (signal traces) rather than guesswork:
- A reset race where the first transaction could be driven before reset was released
- A driver/DUT signal race from driving inputs on the same edge the DUT samples them
- A monitor sampling `rd_data` before the DUT's non-blocking assignment had settled
- A monitor status-flag race where `empty` transitioning on the same edge as a successful read caused that read to be silently dropped

Each was root-caused and fixed with an understanding of SystemVerilog's non-blocking assignment semantics, not trial and error.

## Running the Tests

**On EDA Playground** (no local install needed):
1. Simulator: Cadence Xcelium 25.03, UVM 1.2
2. Files: `design.sv` = `rtl/sync_fifo.v`; `testbench.sv` = `uvm/tb_top.sv`; add `fifo_if.sv`, `fifo_assertions.sv`, `fifo_pkg.sv` as extra files
3. Compile options: `-timescale 1ns/1ns -coverage u`

**Locally**, with a SystemVerilog/UVM simulator on your PATH:
```bash
./run_regression.sh
```

## Repository Structure
```
rtl/                    Synthesizable FIFO design
tb/                     Directed, non-UVM testbench
uvm/                    Full UVM verification environment
    fifo_if.sv          DUT interface
    fifo_pkg.sv         Transactions, sequences, driver, monitor, scoreboard, coverage, env, test
    fifo_assertions.sv  SVA protocol checker (bind-based)
    tb_top.sv           Top-level module, clock/reset, run_test()
run_regression.sh       Regression script
```

## Skills Demonstrated
SystemVerilog, UVM (sequences, driver/monitor/scoreboard, agent/env/test hierarchy), constrained-random verification, functional coverage (coverpoints + crosses), SystemVerilog Assertions, `bind`-based checker architecture, race-condition debugging via signal tracing, Git/GitHub workflow.
