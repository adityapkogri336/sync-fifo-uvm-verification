#!/bin/bash
# ============================================================
# run_regression.sh
#
# Regression script for the synchronous FIFO UVM verification
# environment. Compiles the design + testbench and runs the
# full test (directed + constrained-random + coverage + SVA),
# then reports a clean pass/fail summary.
#
# Requires a SystemVerilog/UVM simulator on the PATH.
# Tested against Cadence Xcelium (xrun). Swap the SIM_CMD below
# if you're using a different tool (Questa: vsim/vlog/vopt,
# VCS: vcs/simv).
# ============================================================

set -e

RTL_DIR="rtl"
UVM_DIR="uvm"
LOG_FILE="regression.log"

echo "=========================================="
echo " Sync FIFO UVM Regression"
echo "=========================================="

xrun -q -unbuffered \
    -timescale 1ns/1ns \
    -coverage u \
    -access +rw \
    -uvmnocdnsextra \
    "$RTL_DIR/sync_fifo.v" \
    "$UVM_DIR/tb_top.sv" \
    2>&1 | tee "$LOG_FILE"

echo ""
echo "=========================================="
echo " Regression Summary"
echo "=========================================="

ERRORS=$(grep -c "UVM_ERROR :" "$LOG_FILE" || true)
FATALS=$(grep -c "UVM_FATAL :" "$LOG_FILE" || true)
COVERAGE=$(grep "Overall functional coverage" "$LOG_FILE" | tail -1)

grep "UVM_ERROR :\|UVM_FATAL :" "$LOG_FILE" || true
echo "$COVERAGE"

if grep -q "UVM_ERROR :    0" "$LOG_FILE" && grep -q "UVM_FATAL :    0" "$LOG_FILE"; then
    echo "RESULT: PASS - 0 errors, 0 fatals"
    exit 0
else
    echo "RESULT: FAIL - see $LOG_FILE for details"
    exit 1
fi
