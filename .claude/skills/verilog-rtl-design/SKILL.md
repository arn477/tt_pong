---
name: verilog-rtl-design
description: Conventions for writing synthesizable Verilog-2005 RTL for Tiny Tapeout (Yosys/OpenLane flow). Use whenever writing or editing any file in src/ - adapted from hdl-module-design for Verilog, which lacks logic/enum/package/always_ff/always_comb.
---

# Verilog RTL design (Tiny Tapeout)

RTL in `src/` is **Verilog-2005 (`.v`)**. Only the testbench may use SystemVerilog (see `verilog-testbench-design`). Same principles as `hdl-module-design`, translated to what Verilog offers.

## Principles

- **Parameterize widths and sizes** with `parameter`/`localparam`; derive widths with `$clog2`. No literal widths scattered through the code.
- **Shared constants, not enums/packages.** Put geometry, speeds, and encodings in `src/pong_defs.vh` as `` `define `` macros or `localparam`s and `` `include "pong_defs.vh" `` (the test Makefile already passes `-I src`). Always use the name, never the raw value: `if (state == S_SERVE)`, not `2'b01`. For state machines, declare `localparam [1:0] S_IDLE = 2'd0, ...` and a `default:` branch in every `case` (Verilog has no `unique case`).
- **Synchronous, active-low reset only** (`rst_n` from the TT harness). Never derive a reset or flush into a sensitivity list.
- **Behavioral, not gate-level.** Use `+`, `<`, `? :`, `case`; no hand-instantiated gates.
- **Loops/generate for repeated structure.** `genvar` + `generate for` for replicated hardware; `integer i` (declared outside the block) for loops inside `always`.
- **Inline muxes** as `assign y = sel ? a : b;`. Use `always @*` only for multi-statement or `case` logic.
- **Header comment** on every module: 1-2 sentences on behavior and non-obvious timing (e.g. "updates only on `frame_tick`").

## Verilog-specific rules

- `` `default_nettype none `` at the top of every file (the TT template does this); declare every wire.
- Type mapping: `logic` -> `wire` (driven by `assign`/ports) or `reg` (assigned in `always`). `always_ff` -> `always @(posedge clk)`. `always_comb` -> `always @*`.
- Sequential blocks use nonblocking `<=`; combinational blocks use blocking `=`. Never mix in one block.
- Clean two-block style for non-trivial state: `always @*` computes `x_d` (next value, defaults first so no latches), `always @(posedge clk)` registers `x_q <= x_d`. Name regs `*_q`, next values `*_d`.
- Every combinational `if`/`case` must assign every output on every path (default assignment at the top of the block) to avoid inferred latches.
- No `'0`/`'1`; write `{W{1'b0}}` or sized literals (`10'd0`). Always size literals.
- Use `signed` explicitly when needed; otherwise keep positions unsigned and compare against clamped limits so there is no wraparound (check `pos + vel` using a wider intermediate if it can overflow).
- No `initial` blocks, `#` delays, `$display`, or `real` in synthesizable files.
- Unused inputs: `wire _unused = &{ena, 1'b0, ...};` (keeps lint clean, per template).

## Templates

Module declaration (ANSI style, parameters then ports, one per line, grouped):

```verilog
`default_nettype none

/*
 * Counts pixel position for 640x480@60. frame_tick pulses one clock at the
 * start of vertical blanking.
 */
module vga_sync #(
    parameter H_TOTAL = 800,
    parameter V_TOTAL = 525
) (
    input  wire       clk,
    input  wire       rst_n,

    output reg  [9:0] h_cnt,
    output reg  [9:0] v_cnt,
    output wire       hsync,
    output wire       vsync,
    output wire       active,
    output wire       frame_tick
);
```

Instantiation: parameter overrides on their own lines, named column-aligned ports:

```verilog
vga_sync #(
    .H_TOTAL (800)
) u_vga (
    .clk        (clk       ),
    .rst_n      (rst_n     ),

    .h_cnt      (h_cnt     ),
    .v_cnt      (v_cnt     ),
    .frame_tick (frame_tick)
);
```

Synchronous reset + loop-free register:

```verilog
always @(posedge clk) begin
    if (!rst_n)      p1_y_q <= PADDLE_START;
    else if (tick)   p1_y_q <= p1_y_d;
end
```

TT top-level: keep the fixed port list from the template (`ui_in, uo_out, uio_in, uio_out, uio_oe, ena, clk, rst_n`); assign every output; update `info.yaml` (`top_module`, `source_files`, pinout) and `PROJECT_SOURCES` in `test/Makefile` whenever a file is added.
