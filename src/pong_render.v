/*
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

/*
 * Combinational pixel generator: maps the beam position and the game state to
 * a 6-bit color {R[1:0], G[1:0], B[1:0]} using range comparators only.
 * Priority: ball > paddles > bricks > score boxes > net > background. Black
 * whenever active is low. In brick breaker mode (mode = 1) the brick wall is
 * drawn and the right paddle and the net are hidden.
 */
module pong_render (
    input  wire [9:0] h_cnt,
    input  wire [9:0] v_cnt,
    input  wire       active,
    input  wire       mode,

    input  wire [9:0] p1_y,
    input  wire [9:0] p2_y,
    input  wire [9:0] ball_x,
    input  wire [9:0] ball_y,
    input  wire [2:0] score_l,
    input  wire [2:0] score_r,
    input  wire [31:0] bricks,

    output wire [5:0] rgb
);

`include "pong_defs.vh"

    wire in_ball = (h_cnt >= ball_x) && (h_cnt < ball_x + BALL_SIZE) &&
                   (v_cnt >= ball_y) && (v_cnt < ball_y + BALL_SIZE);

    wire in_p1   = (h_cnt >= PADDLE_L_X) && (h_cnt < PADDLE_L_X + PADDLE_W) &&
                   (v_cnt >= p1_y)       && (v_cnt < p1_y + PADDLE_H);

    wire in_p2   = !mode && (h_cnt >= PADDLE_R_X) && (h_cnt < PADDLE_R_X + PADDLE_W) &&
                   (v_cnt >= p2_y)       && (v_cnt < p2_y + PADDLE_H);

    wire in_net  = !mode && (h_cnt >= NET_X) && (h_cnt < NET_X + NET_W) && v_cnt[4];

    // Bricks: 32x32 px cells, BRICK_LIT pixels of each lit. Column 0 (nearest
    // the paddle) is cyan, column 1 magenta.
    wire [4:0] brick_idx = {h_cnt[5], v_cnt[8:5]};
    wire       in_brick  = mode && (h_cnt[9:6] == BRICK_X_SEL) && bricks[brick_idx] &&
                           (h_cnt[4:0] < BRICK_LIT) && (v_cnt[4:0] < BRICK_LIT);

    // Score boxes: one 8 px cell per point, SCORE_BOX_W pixels of it lit.
    wire [6:0] cell_x   = h_cnt[9:3];
    wire       in_box   = (v_cnt[9:3] == SCORE_ROW) && (h_cnt[2:0] < SCORE_BOX_W);
    wire       in_sc_l  = in_box && (cell_x >= SCORE_L_COL) &&
                          (cell_x < SCORE_L_COL + {4'd0, score_l});
    wire       in_sc_r  = in_box && (cell_x >= SCORE_R_COL) &&
                          (cell_x < SCORE_R_COL + {4'd0, score_r});

    assign rgb = !active          ? COLOR_BLACK  :
                 in_ball          ? COLOR_YELLOW :
                 (in_p1 || in_p2) ? COLOR_WHITE  :
                 in_brick         ? (h_cnt[5] ? COLOR_MAGENTA : COLOR_CYAN) :
                 in_sc_l          ? COLOR_GREEN  :
                 in_sc_r          ? COLOR_RED    :
                 in_net           ? COLOR_GREY   :
                                    COLOR_BLACK;

endmodule
