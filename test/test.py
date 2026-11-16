# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

# Minimal smoke test for the Tiny Tapeout CI (RTL and gate level): reset, then
# check that the VGA sync pulses have the right timing. It only looks at the
# pins, so it also works on the gate-level netlist. The thorough self-checking
# testbenches are tb_pong_game.sv and tb_pong.sv (see run_tests.sh).

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, FallingEdge, RisingEdge, with_timeout
from cocotb.utils import get_sim_time

CLK_NS = 40  # 25 MHz
LINE_NS = 800 * CLK_NS
FRAME_NS = 525 * LINE_NS


@cocotb.test()
async def test_vga_sync(dut):
    clock = Clock(dut.clk, CLK_NS, unit="ns")
    cocotb.start_soon(clock.start())

    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    assert dut.uio_oe.value == 0, "uio pins must all be inputs"

    dut._log.info("Check hsync: 96 clocks low, 800 clock period")
    await with_timeout(FallingEdge(dut.hsync), 2 * LINE_NS, "ns")
    t_fall = get_sim_time("ns")
    await with_timeout(RisingEdge(dut.hsync), 2 * LINE_NS, "ns")
    t_rise = get_sim_time("ns")
    await with_timeout(FallingEdge(dut.hsync), 2 * LINE_NS, "ns")
    t_fall2 = get_sim_time("ns")
    assert t_rise - t_fall == 96 * CLK_NS
    assert t_fall2 - t_fall == LINE_NS

    dut._log.info("Check vsync: 2 lines low, 525 line period")
    await with_timeout(FallingEdge(dut.vsync), 2 * FRAME_NS, "ns")
    t_fall = get_sim_time("ns")
    await with_timeout(RisingEdge(dut.vsync), 2 * FRAME_NS, "ns")
    t_rise = get_sim_time("ns")
    assert t_rise - t_fall == 2 * LINE_NS
    # Colors are blanked during vertical sync.
    assert dut.rgb.value == 0
    await with_timeout(FallingEdge(dut.vsync), 2 * FRAME_NS, "ns")
    t_fall2 = get_sim_time("ns")
    assert t_fall2 - t_fall == FRAME_NS
