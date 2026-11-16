---
name: verilog-testbench-design
description: Conventions for self-checking SystemVerilog testbenches (and a CLI runner) that verify Verilog-2005 RTL in this Tiny Tapeout project. Use when writing or running tests in test/ - adapted from hdl-testbench-design.
---

# SystemVerilog testbench for Verilog RTL

RTL is Verilog; the testbench is SystemVerilog (`test/tb_pong.sv`). Simulator: **Icarus Verilog with `-g2012`**, which is what the TT toolchain ships. Stay inside its supported SV subset: `int`, `logic`, `string`, `task automatic`, `$urandom`, `$finish`, `repeat`/`for`/`while`, immediate `if` checks. **Avoid** classes, `randomize`, concurrent assertions (`assert property`), interfaces, and covergroups; Icarus does not support them. (Verilator `--binary --timing` is the fallback if more is needed.)

## Principles (same as hdl-testbench-design)

- **Self-checking.** Every check compares actual vs expected with `===` (catches X/Z), prints `[PASS]`/`[FAIL]`, and bumps a counter. End with one greppable line: `TESTBENCH_RESULT: PASS` or `FAIL`.
- **One task per scenario**, descriptively named (`test_vga_timing`, `test_paddle_clamp`, `test_ball_bounce_wall`, `test_score_and_serve`, `test_game_over`, `test_render_pixels`). Shared helpers: `do_reset`, `wait_frames(n)`, `press(buttons, frames)`.
- **Count frames, not cycles.** Frame = 800x525 clocks; use `wait_frames` keyed off `dut.frame_tick`. Run past the minimum, not exact.
- **Trust the simulator, then verify.** Dump actual state, sanity-check against the spec in `docs/info.md`, then bake it in as the expected value.
- **Hierarchical references** into the DUT (`dut.game.ball_x_q`) are fine for checking internal state; to force a scenario, set state via hierarchical assignment after reset, sparingly (prefer driving inputs).
- **Real exit code.** The runner exits 0 only if `TESTBENCH_RESULT: PASS` is present and no `[FAIL]` appears; a missing sentinel (hang/crash) is a failure.
- **Refactoring RTL:** keep the previous version as a golden model and diff outputs bit-for-bit for the same input sequence.

## Templates

Checker and sequencer:

```systemverilog
int pass_count = 0;
int fail_count = 0;

task automatic check(input string name, input logic [31:0] actual, input logic [31:0] expected);
    if (actual === expected) begin
        pass_count++;
        $display("[PASS] %-32s = %0d", name, actual);
    end else begin
        fail_count++;
        $display("[FAIL] %-32s = %0d, expected %0d", name, actual, expected);
    end
endtask

task automatic wait_frames(input int n);
    repeat (n) @(posedge clk iff dut.frame_tick);   // if iff is unsupported: while (!dut.frame_tick) @(posedge clk);
endtask

initial begin
    do_reset();
    test_vga_timing();
    test_paddle_clamp();
    // ... one call per scenario
    $display("TESTBENCH_SUMMARY: %0d PASS, %0d FAIL", pass_count, fail_count);
    $display("TESTBENCH_RESULT: %s", (fail_count == 0) ? "PASS" : "FAIL");
    $finish;
end

// Watchdog: a hung sim must not look like a pass.
initial begin
    #(200_000_000);     // ~8 frames at 40 ns/clk x 420k clks/frame; scale to test length
    $display("TESTBENCH_RESULT: FAIL (timeout)");
    $finish;
end
```

DUT wiring: instantiate the TT top directly (`tt_um_<user>_pong dut (.ui_in, .uo_out, .uio_in, .uio_out, .uio_oe, .ena(1'b1), .clk, .rst_n)`), decode `uo_out` into `hsync = uo_out[7]`, `vsync = uo_out[3]`, `rgb` bits per the pinout in `docs/info.md`. Clock: `always #20 clk = ~clk;` (25 MHz) with `` `timescale 1ns/1ps ``. Hold `rst_n` low for several clocks, release on a negedge.

## Runner (`test/run_tests.sh`)

```bash
#!/usr/bin/env bash
set -u
cd "$(dirname "${BASH_SOURCE[0]}")"
SRC=../src
mkdir -p sim_build
if ! iverilog -g2012 -I $SRC -o sim_build/tb_pong.vvp \
     $SRC/vga_sync.v $SRC/input_sync.v $SRC/pong_game.v $SRC/pong_render.v $SRC/project.v tb_pong.sv \
     > sim_build/compile.log 2>&1; then
    cat sim_build/compile.log; echo "==> COMPILE FAILED"; exit 1
fi
vvp sim_build/tb_pong.vvp > sim_build/sim.log 2>&1
cat sim_build/sim.log
if grep -q 'TESTBENCH_RESULT: PASS' sim_build/sim.log && ! grep -q '\[FAIL\]' sim_build/sim.log; then
    exit 0
fi
echo "==> TESTBENCH_RESULT: FAIL (or no result - check sim.log)"; exit 1
```

Keep the source list in sync with `info.yaml` `source_files` and `PROJECT_SOURCES` in `test/Makefile`. The cocotb `test.py`/`tb.v` template stays for TT CI; keep a minimal smoke test there so the GitHub `test` workflow passes.
