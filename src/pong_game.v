/*
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

/*
 * Game state for both games: paddles, ball, scores, bricks. Everything except
 * the LFSR updates only on frame_tick (once per frame, during vertical
 * blanking), so the renderer never sees a half-updated frame.
 *
 * mode = 0: two-player Pong. mode = 1: one-player brick breaker, which reuses
 * the ball and the left paddle; the right edge is a wall, a 2x15 brick wall
 * stands in front of it, and score_r counts missed balls. mode must only be
 * changed while in reset.
 *
 * Velocities are stored as direction bits with constant magnitude:
 * ball_vx_neg_q = 1 -> moving left, ball_vy_neg_q = 1 -> moving up.
 * Player 1 is the left paddle, player 2 the right paddle.
 */
module pong_game (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       frame_tick,
    input  wire       mode,

    input  wire       p1_up,
    input  wire       p1_down,
    input  wire       p2_up,
    input  wire       p2_down,

    output wire [9:0] p1_y,
    output wire [9:0] p2_y,
    output wire [9:0] ball_x,
    output wire [9:0] ball_y,
    output wire [2:0] score_l,
    output wire [2:0] score_r,
    output wire [31:0] bricks
);

`include "pong_defs.vh"

    reg [9:0] p1_y_q, p2_y_q;
    reg [9:0] ball_x_q, ball_y_q;
    reg       ball_vx_neg_q, ball_vy_neg_q;
    reg [2:0] score_l_q, score_r_q;
    reg [3:0] lfsr_q;
    reg [31:0] bricks_q;

    reg [9:0] ball_x_d, ball_y_d;
    reg       ball_vx_neg_d, ball_vy_neg_d;
    reg [2:0] score_l_d, score_r_d;

    // ---------------- Paddles ----------------
    // up: -PADDLE_SPEED, down: +PADDLE_SPEED, both/neither: hold. Clamped to
    // [0, PADDLE_Y_MAX] without ever wrapping.
    function [9:0] paddle_next;
        input [9:0] y;
        input       up;
        input       down;
        begin
            paddle_next = y;
            if (up && !down)
                paddle_next = (y < PADDLE_SPEED) ? 10'd0 : y - PADDLE_SPEED;
            else if (down && !up)
                paddle_next = (y > PADDLE_Y_MAX - PADDLE_SPEED) ? PADDLE_Y_MAX : y + PADDLE_SPEED;
        end
    endfunction

    wire [9:0] p1_y_d = paddle_next(p1_y_q, p1_up, p1_down);
    wire [9:0] p2_y_d = paddle_next(p2_y_q, p2_up, p2_down);

    // ---------------- Ball: vertical ----------------
    wire [9:0] y_up     = ball_y_q - BALL_VY;
    wire [9:0] y_down   = ball_y_q + BALL_VY;
    wire       hits_top = (ball_y_q <= BALL_VY);
    wire       hits_bot = (y_down >= BALL_Y_MAX);

    // Next y after wall clamp, and the direction after a wall bounce.
    wire [9:0] next_y      = ball_vy_neg_q ? (hits_top ? 10'd0      : y_up)
                                           : (hits_bot ? BALL_Y_MAX : y_down);
    wire       vy_neg_wall = ball_vy_neg_q ? !hits_top : hits_bot;

    // ---------------- Ball: horizontal ----------------
    // next_x may wrap when the ball leaves on the left; out_l has priority
    // over every use of next_x in that case.
    wire [9:0] next_x = ball_vx_neg_q ? ball_x_q - BALL_VX : ball_x_q + BALL_VX;

    wire       out_l  =  ball_vx_neg_q && (ball_x_q < BALL_VX);
    wire       out_r  = !mode && !ball_vx_neg_q && (next_x >  BALL_X_MAX);
    // Brick breaker: the right edge is a solid wall.
    wire       wall_r =  mode && !ball_vx_neg_q && (next_x >= BALL_X_MAX);

    // Only the paddle the ball is moving towards can be hit.
    wire [9:0] pad_y     = ball_vx_neg_q ? p1_y_q : p2_y_q;
    wire       y_overlap = (next_y + BALL_SIZE > pad_y) && (next_y < pad_y + PADDLE_H);

    // The ball is in front of the paddle face now and would touch or cross it
    // this frame (crossing check, so no tunnelling and no repeated bounces).
    wire       hit_l =  ball_vx_neg_q && (ball_x_q > BALL_X_HIT_L)
                                      && (next_x <= BALL_X_HIT_L) && y_overlap;
    wire       hit_r = !mode && !ball_vx_neg_q && (ball_x_q < BALL_X_HIT_R)
                                      && (next_x >= BALL_X_HIT_R) && y_overlap;

    wire [9:0] ball_ctr   = next_y + BALL_HALF;
    wire       zone_upper = (ball_ctr <  pad_y + ZONE_UPPER);
    wire       zone_lower = (ball_ctr >= pad_y + ZONE_LOWER);

    // ---------------- Bricks (mode = 1) ----------------
    // One probe point: the ball's leading edge in x, its centre in y. If the
    // probe's next position is inside a live brick, that brick is removed and
    // the ball stays where it is for this frame with one direction flipped:
    // vx if the probe entered the cell through a vertical face, else vy.
    wire [9:0] probe_x_cur = ball_vx_neg_q ? ball_x_q : ball_x_q + BALL_EDGE;
    wire [9:0] probe_x_nxt = ball_vx_neg_q ? next_x   : next_x   + BALL_EDGE;
    wire [9:0] probe_y_nxt = next_y + BALL_HALF;

    wire [4:0] brick_idx   = {probe_x_nxt[5], probe_y_nxt[8:5]};
    wire       brick_hit   = mode && (probe_x_nxt[9:6] == BRICK_X_SEL) && bricks_q[brick_idx];
    wire       brick_side  = (probe_x_cur[9:5] != probe_x_nxt[9:5]);

    // Pong: first to SCORE_MAX. Brick breaker: MISSES_MAX misses, or the
    // wall is cleared.
    wire       game_over  = mode ? ((score_r_q == MISSES_MAX) || (bricks_q == 32'd0))
                                 : ((score_l_q == SCORE_MAX) || (score_r_q == SCORE_MAX));

    always @* begin
        ball_x_d      = next_x;
        ball_y_d      = next_y;
        ball_vx_neg_d = ball_vx_neg_q;
        ball_vy_neg_d = vy_neg_wall;
        score_l_d     = score_l_q;
        score_r_d     = score_r_q;

        if (game_over) begin
            // Frozen (at the serve position) until reset.
            ball_x_d      = ball_x_q;
            ball_y_d      = ball_y_q;
            ball_vy_neg_d = ball_vy_neg_q;
        end else if (out_l || out_r) begin
            // Point scored: re-serve from the centre towards the loser.
            ball_x_d      = BALL_X_START;
            ball_y_d      = BALL_Y_START;
            ball_vx_neg_d = out_l;
            ball_vy_neg_d = lfsr_q[0];
            if (out_l) score_r_d = score_r_q + 3'd1;
            else       score_l_d = score_l_q + 3'd1;
        end else if (brick_hit) begin
            ball_x_d      = ball_x_q;
            ball_y_d      = ball_y_q;
            ball_vx_neg_d = ball_vx_neg_q ^ brick_side;
            ball_vy_neg_d = ball_vy_neg_q ^ !brick_side;
        end else if (wall_r) begin
            ball_x_d      = BALL_X_MAX;
            ball_vx_neg_d = 1'b1;
        end else if (hit_l || hit_r) begin
            // Paddle bounce: rest on the paddle face, head away from it.
            ball_x_d      = hit_l ? BALL_X_HIT_L : BALL_X_HIT_R;
            ball_vx_neg_d = hit_r;
            if (zone_upper)      ball_vy_neg_d = 1'b1;
            else if (zone_lower) ball_vy_neg_d = 1'b0;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            p1_y_q        <= PADDLE_Y_START;
            p2_y_q        <= PADDLE_Y_START;
            ball_x_q      <= BALL_X_START;
            ball_y_q      <= BALL_Y_START;
            ball_vx_neg_q <= 1'b0;
            ball_vy_neg_q <= 1'b0;
            score_l_q     <= 3'd0;
            score_r_q     <= 3'd0;
        end else if (frame_tick) begin
            p1_y_q        <= p1_y_d;
            p2_y_q        <= p2_y_d;
            ball_x_q      <= ball_x_d;
            ball_y_q      <= ball_y_d;
            ball_vx_neg_q <= ball_vx_neg_d;
            ball_vy_neg_q <= ball_vy_neg_d;
            score_l_q     <= score_l_d;
            score_r_q     <= score_r_d;
        end
    end

    always @(posedge clk) begin
        if (!rst_n)
            bricks_q <= BRICKS_FULL;
        else if (frame_tick && brick_hit && !game_over)
            bricks_q[brick_idx] <= 1'b0;
    end

    // ---------------- Serve randomness ----------------
    // 4-bit maximal LFSR (x^4 + x^3 + 1, period 15). A frame is 420000
    // clocks = 0 mod 15, so stepping every clock would give the same value
    // at every frame_tick. Instead it steps once per frame and on every
    // clock while any button is held, so the players' timing is the entropy.
    wire lfsr_step = frame_tick || p1_up || p1_down || p2_up || p2_down;

    always @(posedge clk) begin
        if (!rst_n)         lfsr_q <= LFSR_SEED;
        else if (lfsr_step) lfsr_q <= {lfsr_q[2:0], lfsr_q[3] ^ lfsr_q[2]};
    end

    assign p1_y    = p1_y_q;
    assign p2_y    = p2_y_q;
    assign ball_x  = ball_x_q;
    assign ball_y  = ball_y_q;
    assign score_l = score_l_q;
    assign score_r = score_r_q;
    assign bricks  = bricks_q;

endmodule
