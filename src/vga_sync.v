/*
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

/*
 * Pixel/line counters and sync generation for 640x480 @ 60 Hz (one pixel per
 * clock). hsync/vsync are active low. frame_tick pulses for one clock at the
 * start of vertical blanking (h_cnt == 0, v_cnt == V_VISIBLE).
 */
module vga_sync (
    input  wire       clk,
    input  wire       rst_n,

    output reg  [9:0] h_cnt,
    output reg  [9:0] v_cnt,
    output wire       hsync,
    output wire       vsync,
    output wire       active,
    output wire       frame_tick
);

`include "pong_defs.vh"

    wire h_last = (h_cnt == H_TOTAL - 10'd1);
    wire v_last = (v_cnt == V_TOTAL - 10'd1);

    always @(posedge clk) begin
        if (!rst_n) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
        end else if (h_last) begin
            h_cnt <= 10'd0;
            v_cnt <= v_last ? 10'd0 : v_cnt + 10'd1;
        end else begin
            h_cnt <= h_cnt + 10'd1;
        end
    end

    assign hsync      = ~((h_cnt >= H_SYNC_START) && (h_cnt < H_SYNC_END));
    assign vsync      = ~((v_cnt >= V_SYNC_START) && (v_cnt < V_SYNC_END));
    assign active     = (h_cnt < H_VISIBLE) && (v_cnt < V_VISIBLE);
    assign frame_tick = (h_cnt == 10'd0) && (v_cnt == V_VISIBLE);

endmodule
