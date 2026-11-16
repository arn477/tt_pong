/*
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

/*
 * Tiny Tapeout top level for two-player VGA Pong. Maps the four buttons on
 * ui_in[3:0] and drives a Tiny VGA PMOD on uo_out. Colors and syncs are
 * registered together, so the output lags the counters by one pixel.
 */
module tt_um_pong (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

    wire [3:0] btn;             // {p2_down, p2_up, p1_down, p1_up}

    wire [9:0] h_cnt;
    wire [9:0] v_cnt;
    wire       hsync;
    wire       vsync;
    wire       active;
    wire       frame_tick;

    wire [9:0] p1_y;
    wire [9:0] p2_y;
    wire [9:0] ball_x;
    wire [9:0] ball_y;
    wire [2:0] score_l;
    wire [2:0] score_r;

    wire [5:0] rgb;             // {R1, R0, G1, G0, B1, B0}

    input_sync #(
        .WIDTH (4)
    ) btn_sync (
        .clk      (clk       ),
        .rst_n    (rst_n     ),

        .async_in (ui_in[3:0]),
        .sync_out (btn       )
    );

    vga_sync vga (
        .clk        (clk       ),
        .rst_n      (rst_n     ),

        .h_cnt      (h_cnt     ),
        .v_cnt      (v_cnt     ),
        .hsync      (hsync     ),
        .vsync      (vsync     ),
        .active     (active    ),
        .frame_tick (frame_tick)
    );

    pong_game game (
        .clk        (clk       ),
        .rst_n      (rst_n     ),
        .frame_tick (frame_tick),

        .p1_up      (btn[0]    ),
        .p1_down    (btn[1]    ),
        .p2_up      (btn[2]    ),
        .p2_down    (btn[3]    ),

        .p1_y       (p1_y      ),
        .p2_y       (p2_y      ),
        .ball_x     (ball_x    ),
        .ball_y     (ball_y    ),
        .score_l    (score_l   ),
        .score_r    (score_r   )
    );

    pong_render render (
        .h_cnt   (h_cnt  ),
        .v_cnt   (v_cnt  ),
        .active  (active ),

        .p1_y    (p1_y   ),
        .p2_y    (p2_y   ),
        .ball_x  (ball_x ),
        .ball_y  (ball_y ),
        .score_l (score_l),
        .score_r (score_r),

        .rgb     (rgb    )
    );

    // Output registers: glitch-free pins, color and sync delayed together.
    reg [5:0] rgb_q;
    reg       hsync_q;
    reg       vsync_q;

    always @(posedge clk) begin
        if (!rst_n) begin
            rgb_q   <= 6'd0;
            hsync_q <= 1'b1;
            vsync_q <= 1'b1;
        end else begin
            rgb_q   <= rgb;
            hsync_q <= hsync;
            vsync_q <= vsync;
        end
    end

    // Tiny VGA PMOD: {HSYNC, B0, G0, R0, VSYNC, B1, G1, R1}
    assign uo_out  = {hsync_q, rgb_q[0], rgb_q[2], rgb_q[4],
                      vsync_q, rgb_q[1], rgb_q[3], rgb_q[5]};
    assign uio_out = 8'd0;
    assign uio_oe  = 8'd0;

    // List all unused inputs to prevent warnings
    wire _unused = &{ena, ui_in[7:4], uio_in, 1'b0};

endmodule
