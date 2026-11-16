#!/usr/bin/env bash
# Compiles the RTL with each self-checking testbench, runs it, and exits 0 only
# if every testbench prints TESTBENCH_RESULT: PASS with no [FAIL] lines.
# Uses Icarus Verilog if installed, otherwise Questa/ModelSim (vlog/vsim).
# Usage: ./run_tests.sh [tb_name ...]     (default: all testbenches)
set -u
cd "$(dirname "${BASH_SOURCE[0]}")"

SRC=../src
RTL="$SRC/vga_sync.v $SRC/input_sync.v $SRC/pong_game.v $SRC/pong_render.v $SRC/project.v"
TESTBENCHES="${*:-tb_pong_game tb_pong}"
BUILD=sim_build
mkdir -p "$BUILD"

if command -v iverilog >/dev/null 2>&1; then
    SIM=icarus
elif command -v vsim >/dev/null 2>&1; then
    SIM=questa
else
    echo "==> No simulator found (need iverilog or vlog/vsim on PATH)"; exit 1
fi
echo "==> Simulator: $SIM"

# The RTL must be plain Verilog-2005 (the testbenches are SystemVerilog).
if [ "$SIM" = icarus ]; then
    if ! iverilog -g2005 -Wall -I "$SRC" -o "$BUILD/rtl_only.vvp" $RTL > "$BUILD/rtl_compile.log" 2>&1; then
        cat "$BUILD/rtl_compile.log"; echo "==> RTL COMPILE FAILED (Verilog-2005)"; exit 1
    fi
else
    rm -rf "$BUILD/work"
    vlib "$BUILD/work" > /dev/null
    if ! vlog -quiet -vlog01compat -lint -work "$BUILD/work" +incdir+"$SRC" $RTL > "$BUILD/rtl_compile.log" 2>&1; then
        cat "$BUILD/rtl_compile.log"; echo "==> RTL COMPILE FAILED (Verilog-2005)"; exit 1
    fi
fi
cat "$BUILD/rtl_compile.log"

status=0
for tb in $TESTBENCHES; do
    echo "==> $tb"
    log="$BUILD/$tb.log"
    if [ "$SIM" = icarus ]; then
        if ! iverilog -g2012 -I "$SRC" -s "$tb" -o "$BUILD/$tb.vvp" $RTL "$tb.sv" > "$BUILD/$tb.compile.log" 2>&1; then
            cat "$BUILD/$tb.compile.log"; echo "==> $tb: COMPILE FAILED"; status=1; continue
        fi
        vvp "$BUILD/$tb.vvp" > "$log" 2>&1
    else
        if ! vlog -quiet -sv -work "$BUILD/work" "$tb.sv" > "$BUILD/$tb.compile.log" 2>&1; then
            cat "$BUILD/$tb.compile.log"; echo "==> $tb: COMPILE FAILED"; status=1; continue
        fi
        vsim -c -quiet -l "$BUILD/$tb.transcript" -voptargs=+acc -work "$BUILD/work" "$tb" -do "run -all; quit -f" > "$log" 2>&1
    fi
    cat "$log"
    if grep -q 'TESTBENCH_RESULT: PASS' "$log" && ! grep -q '\[FAIL\]' "$log"; then
        echo "==> $tb: PASS"
    else
        echo "==> $tb: FAIL (or no result - check $BUILD/$tb.log)"; status=1
    fi
done

if [ $status -eq 0 ]; then echo "==> ALL TESTBENCHES PASSED"; else echo "==> SOME TESTBENCHES FAILED"; fi
exit $status
