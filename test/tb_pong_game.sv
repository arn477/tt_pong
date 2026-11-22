`default_nettype none
`timescale 1ns / 1ps

// Unit testbench for pong_game. frame_tick is driven directly (one tick every
// few clocks) so hundreds of game frames simulate in milliseconds. Expected
// values come from the rules in docs/info.md.
module tb_pong_game;

    logic       clk = 1'b0;
    logic       rst_n = 1'b0;
    logic       frame_tick = 1'b0;
    logic [3:0] btn = 4'b0000;      // {p2_down, p2_up, p1_down, p1_up}
    logic       mode = 1'b0;        // 0 = Pong, 1 = brick breaker

    wire  [9:0] p1_y, p2_y, ball_x, ball_y;
    wire  [2:0] score_l, score_r;
    wire  [31:0] bricks;

    localparam logic [31:0] BRICKS_FULL = 32'h7FFF_7FFF;    // 2 columns x 15 rows

    localparam logic [3:0] P1_UP = 4'b0001, P1_DOWN = 4'b0010, P2_UP = 4'b0100, P2_DOWN = 4'b1000;

    pong_game dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .frame_tick (frame_tick),
        .mode       (mode),
        .p1_up      (btn[0]),
        .p1_down    (btn[1]),
        .p2_up      (btn[2]),
        .p2_down    (btn[3]),
        .p1_y       (p1_y),
        .p2_y       (p2_y),
        .ball_x     (ball_x),
        .ball_y     (ball_y),
        .score_l    (score_l),
        .score_r    (score_r),
        .bricks     (bricks)
    );

    always #20 clk = ~clk;

    int pass_count = 0;
    int fail_count = 0;

    task automatic check(input string name, input logic [31:0] actual, input logic [31:0] expected);
        if (actual === expected) begin
            pass_count++;
            $display("[PASS] %-40s = %0d", name, actual);
        end else begin
            fail_count++;
            $display("[FAIL] %-40s = %0d, expected %0d", name, actual, expected);
        end
    endtask

    // ---------------- helpers ----------------
    task automatic do_reset();
        btn        = 4'b0000;
        frame_tick = 1'b0;
        rst_n      = 1'b0;
        repeat (4) @(negedge clk);
        rst_n      = 1'b1;
        @(negedge clk);
    endtask

    // Advance the game by n frames. Returns on a negedge with the state settled.
    task automatic tick(input int n);
        repeat (n) begin
            @(negedge clk);
            frame_tick = 1'b1;
            @(negedge clk);
            frame_tick = 1'b0;
        end
    endtask

    // Place the ball (between ticks). left/up are the velocity direction bits.
    task automatic set_ball(input int x, input int y, input logic left, input logic up);
        @(negedge clk);
        dut.ball_x_q      = x[9:0];
        dut.ball_y_q      = y[9:0];
        dut.ball_vx_neg_q = left;
        dut.ball_vy_neg_q = up;
    endtask

    task automatic check_ball(input string name, input int x, input int y, input logic left, input logic up);
        check({name, " ball_x"}, ball_x, x);
        check({name, " ball_y"}, ball_y, y);
        check({name, " vx_neg"}, dut.ball_vx_neg_q, left);
        check({name, " vy_neg"}, dut.ball_vy_neg_q, up);
    endtask

    // ---------------- scenarios ----------------
    task automatic test_reset();
        $display("--- test_reset");
        do_reset();
        check("reset p1_y", p1_y, 208);
        check("reset p2_y", p2_y, 208);
        check_ball("reset", 316, 236, 1'b0, 1'b0);
        check("reset score_l", score_l, 0);
        check("reset score_r", score_r, 0);
        // Nothing moves without a frame tick.
        btn = P1_UP | P2_DOWN;
        repeat (20) @(negedge clk);
        btn = 4'b0000;
        check("no tick: p1_y holds", p1_y, 208);
        check("no tick: p2_y holds", p2_y, 208);
        check("no tick: ball_x holds", ball_x, 316);
    endtask

    task automatic test_paddle_move();
        $display("--- test_paddle_move");
        do_reset();
        btn = P1_UP;            tick(3);
        check("p1 up x3", p1_y, 196);
        check("p2 unaffected", p2_y, 208);
        btn = P1_DOWN;          tick(2);
        check("p1 down x2", p1_y, 204);
        btn = P1_UP | P1_DOWN;  tick(2);
        check("p1 up+down holds", p1_y, 204);
        btn = P2_DOWN;          tick(1);
        check("p2 down x1", p2_y, 212);
        check("p1 unaffected", p1_y, 204);
        btn = P2_UP;            tick(2);
        check("p2 up x2", p2_y, 204);
        btn = P2_UP | P2_DOWN;  tick(2);
        check("p2 up+down holds", p2_y, 204);
        btn = 4'b0000;          tick(2);
        check("p1 idle holds", p1_y, 204);
        check("p2 idle holds", p2_y, 204);
    endtask

    task automatic test_paddle_clamp();
        $display("--- test_paddle_clamp");
        do_reset();
        btn = P1_UP | P2_UP;     tick(60);      // 208/4 = 52 frames to the top
        check("p1 clamps at top", p1_y, 0);
        check("p2 clamps at top", p2_y, 0);
        btn = P1_DOWN | P2_DOWN; tick(110);     // 416/4 = 104 frames to the bottom
        check("p1 clamps at bottom", p1_y, 416);
        check("p2 clamps at bottom", p2_y, 416);
        // Non-multiple-of-speed positions must clamp, not wrap.
        @(negedge clk); dut.p1_y_q = 10'd2; dut.p2_y_q = 10'd415;
        btn = P1_UP | P2_DOWN;   tick(1);
        check("p1 clamps from y=2", p1_y, 0);
        check("p2 clamps from y=415", p2_y, 416);
        btn = 4'b0000;
    endtask

    task automatic test_ball_motion();
        $display("--- test_ball_motion");
        do_reset();
        tick(1);
        check_ball("frame 1", 320, 239, 1'b0, 1'b0);
        tick(2);
        check_ball("frame 3", 328, 245, 1'b0, 1'b0);
        set_ball(300, 200, 1'b1, 1'b1);
        tick(2);
        check_ball("left/up x2", 292, 194, 1'b1, 1'b1);
    endtask

    task automatic test_ball_bounce_wall();
        $display("--- test_ball_bounce_wall");
        do_reset();
        set_ball(300, 467, 1'b0, 1'b0);
        tick(1);  check_ball("near bottom", 304, 470, 1'b0, 1'b0);
        tick(1);  check_ball("bottom bounce", 308, 472, 1'b0, 1'b1);
        tick(1);  check_ball("after bottom", 312, 469, 1'b0, 1'b1);
        set_ball(300, 5, 1'b1, 1'b1);
        tick(1);  check_ball("near top", 296, 2, 1'b1, 1'b1);
        tick(1);  check_ball("top bounce", 292, 0, 1'b1, 1'b0);
        tick(1);  check_ball("after top", 288, 3, 1'b1, 1'b0);
        // Landing exactly on the wall bounces in the same frame.
        set_ball(300, 469, 1'b0, 1'b0);
        tick(1);  check_ball("exact bottom", 304, 472, 1'b0, 1'b1);
        set_ball(300, 3, 1'b0, 1'b1);
        tick(1);  check_ball("exact top", 304, 0, 1'b0, 1'b0);
    endtask

    task automatic test_ball_bounce_paddle();
        $display("--- test_ball_bounce_paddle");
        do_reset();                                 // paddles at y = 208..271
        // Left paddle, middle zone: vy unchanged.
        set_ball(32, 236, 1'b1, 1'b0);
        tick(1);  check_ball("L approach", 28, 239, 1'b1, 1'b0);
        tick(1);  check_ball("L middle hit", 24, 242, 1'b0, 1'b0);
        tick(1);  check_ball("L leaving", 28, 245, 1'b0, 1'b0);
        // Left paddle, upper zone: deflect up.
        set_ball(28, 215, 1'b1, 1'b0);
        tick(1);  check_ball("L upper hit", 24, 218, 1'b0, 1'b1);
        // Left paddle, lower zone: deflect down.
        set_ball(28, 250, 1'b1, 1'b1);
        tick(1);  check_ball("L lower hit", 24, 247, 1'b0, 1'b0);
        // Ball not aligned to the speed grid still lands on the paddle face.
        set_ball(26, 236, 1'b1, 1'b0);
        tick(1);  check_ball("L off-grid hit", 24, 239, 1'b0, 1'b0);
        // Just clipping the top / bottom corner counts as a hit.
        set_ball(28, 198, 1'b1, 1'b0);              // next y 201, bottom edge 209 > 208
        tick(1);  check_ball("L top corner hit", 24, 201, 1'b0, 1'b1);
        set_ball(28, 274, 1'b1, 1'b1);              // next y 271 < 272
        tick(1);  check_ball("L bottom corner hit", 24, 271, 1'b0, 1'b0);
        // One pixel further out is a miss: the ball carries on.
        set_ball(28, 197, 1'b1, 1'b0);              // next y 200, bottom edge 208
        tick(1);  check_ball("L miss above", 24, 200, 1'b1, 1'b0);
        tick(1);  check_ball("L miss carries on", 20, 203, 1'b1, 1'b0);
        set_ball(28, 275, 1'b1, 1'b1);              // next y 272
        tick(1);  check_ball("L miss below", 24, 272, 1'b1, 1'b1);

        // Right paddle.
        set_ball(600, 236, 1'b0, 1'b0);
        tick(1);  check_ball("R approach", 604, 239, 1'b0, 1'b0);
        tick(1);  check_ball("R middle hit", 608, 242, 1'b1, 1'b0);
        tick(1);  check_ball("R leaving", 604, 245, 1'b1, 1'b0);
        set_ball(604, 215, 1'b0, 1'b0);
        tick(1);  check_ball("R upper hit", 608, 218, 1'b1, 1'b1);
        set_ball(604, 250, 1'b0, 1'b1);
        tick(1);  check_ball("R lower hit", 608, 247, 1'b1, 1'b0);
        set_ball(604, 197, 1'b0, 1'b0);
        tick(1);  check_ball("R miss above", 608, 200, 1'b0, 1'b0);

        // The paddle the ball is moving away from never bounces it.
        set_ball(20, 236, 1'b0, 1'b0);
        tick(1);  check_ball("moving away from L", 24, 239, 1'b0, 1'b0);

        // Bounce uses the paddle's position, not a fixed one.
        @(negedge clk); dut.p1_y_q = 10'd0;
        set_ball(28, 236, 1'b1, 1'b0);
        tick(1);  check_ball("L paddle moved away", 24, 239, 1'b1, 1'b0);
    endtask

    task automatic test_score_and_serve();
        logic lfsr_bit;
        $display("--- test_score_and_serve");
        do_reset();
        // Ball leaves on the left: right player scores, serve towards the left.
        set_ball(4, 100, 1'b1, 1'b1);
        tick(1);  check_ball("at left edge", 0, 97, 1'b1, 1'b1);
        check("no score yet (r)", score_r, 0);
        lfsr_bit = dut.lfsr_q[0];
        tick(1);
        check("right player scores", score_r, 1);
        check("left score unchanged", score_l, 0);
        check_ball("serve after left out", 316, 236, 1'b1, lfsr_bit);
        // Ball leaves on the right: left player scores, serve towards the right.
        set_ball(628, 100, 1'b0, 1'b0);
        tick(1);  check_ball("at right edge", 632, 103, 1'b0, 1'b0);
        check("no score yet (l)", score_l, 0);
        lfsr_bit = dut.lfsr_q[0];
        tick(1);
        check("left player scores", score_l, 1);
        check("right score unchanged", score_r, 1);
        check_ball("serve after right out", 316, 236, 1'b0, lfsr_bit);
    endtask

    task automatic test_game_over();
        $display("--- test_game_over");
        do_reset();
        @(negedge clk); dut.score_l_q = 3'd6; dut.score_r_q = 3'd2;
        set_ball(632, 100, 1'b0, 1'b0);
        tick(1);
        check("score_l reaches 7", score_l, 7);
        check("score_r unchanged", score_r, 2);
        tick(10);
        check("frozen ball_x", ball_x, 316);
        check("frozen ball_y", ball_y, 236);
        check("score_l stays 7", score_l, 7);
        check("score_r stays 2", score_r, 2);
        btn = P1_UP; tick(1); btn = 4'b0000;
        check("paddles still move", p1_y, 204);
        do_reset();
        check("reset clears score_l", score_l, 0);
        check("reset clears score_r", score_r, 0);

        // Same for the right player.
        @(negedge clk); dut.score_r_q = 3'd6;
        set_ball(0, 100, 1'b1, 1'b0);
        tick(1);
        check("score_r reaches 7", score_r, 7);
        tick(10);
        check("frozen ball_x (r)", ball_x, 316);
        check("score_r stays 7", score_r, 7);
        check("score_l stays 0", score_l, 0);
    endtask

    task automatic test_lfsr();
        logic [3:0] lfsr_prev;
        int         seen;
        $display("--- test_lfsr");
        do_reset();
        check("lfsr seed nonzero", dut.lfsr_q != 4'd0, 1);
        lfsr_prev = dut.lfsr_q;
        repeat (10) @(negedge clk);
        check("lfsr holds when idle", dut.lfsr_q, lfsr_prev);
        tick(1);
        check("lfsr steps on frame tick", dut.lfsr_q != lfsr_prev, 1);
        lfsr_prev = dut.lfsr_q;
        btn = P2_UP; @(negedge clk); @(negedge clk); btn = 4'b0000;
        check("lfsr steps while button held", dut.lfsr_q != lfsr_prev, 1);
        // Maximal length: all 15 nonzero states are visited.
        seen = 0;
        repeat (15) begin
            seen = seen | (1 << dut.lfsr_q);
            tick(1);
        end
        check("lfsr visits 15 states", seen, 32'h0000_FFFE);
    endtask

    // Unforced play from reset: nobody moves, so the first serve is missed.
    task automatic test_first_point();
        $display("--- test_first_point");
        do_reset();
        tick(73);
        check_ball("passes right paddle", 608, 455, 1'b0, 1'b0);
        tick(6);
        check_ball("right edge + wall bounce", 632, 472, 1'b0, 1'b1);
        check("no score at frame 79", score_l, 0);
        tick(1);
        check("left scores at frame 80", score_l, 1);
        check("right has no points", score_r, 0);
        check("re-serve ball_x", ball_x, 316);
        check("re-serve ball_y", ball_y, 236);
        check("re-serve towards right", dut.ball_vx_neg_q, 0);
    endtask

    // Both paddles track the ball through their buttons: the ball must keep
    // bouncing and nobody may score. Also checks the ball never leaves the field.
    task automatic test_rally();
        int   bounces;
        int   out_of_field;
        logic vx_prev;
        $display("--- test_rally");
        do_reset();
        bounces      = 0;
        out_of_field = 0;
        vx_prev      = dut.ball_vx_neg_q;
        repeat (1500) begin
            btn = 4'b0000;
            if      (ball_y + 4 < p1_y + 28) btn = btn | P1_UP;
            else if (ball_y + 4 > p1_y + 36) btn = btn | P1_DOWN;
            if      (ball_y + 4 < p2_y + 28) btn = btn | P2_UP;
            else if (ball_y + 4 > p2_y + 36) btn = btn | P2_DOWN;
            tick(1);
            if (dut.ball_vx_neg_q !== vx_prev) bounces++;
            vx_prev = dut.ball_vx_neg_q;
            if (ball_x > 632 || ball_y > 472 || p1_y > 416 || p2_y > 416) out_of_field++;
        end
        btn = 4'b0000;
        $display("       rally: %0d paddle bounces in 1500 frames", bounces);
        check("rally: no points for left", score_l, 0);
        check("rally: no points for right", score_r, 0);
        check("rally: ball kept bouncing", bounces >= 8, 1);
        check("rally: nothing left the field", out_of_field, 0);
    endtask

    // ================= brick breaker (mode = 1) =================
    function automatic int count_bricks();
        int n;
        n = 0;
        for (int i = 0; i < 32; i++) if (bricks[i]) n++;
        return n;
    endfunction

    task automatic test_brick_reset();
        $display("--- test_brick_reset");
        mode = 1'b1;
        do_reset();
        check("brick: wall full after reset", bricks, BRICKS_FULL);
        check("brick: 30 bricks", count_bricks(), 30);
        check_ball("brick: reset", 316, 236, 1'b0, 1'b0);
        check("brick: no misses", score_r, 0);
    endtask

    // Pong must be unaffected by the brick wall.
    task automatic test_pong_ignores_bricks();
        $display("--- test_pong_ignores_bricks");
        mode = 1'b0;
        do_reset();
        set_ball(500, 100, 1'b0, 1'b0);
        tick(2);
        check_ball("pong: flies through wall area", 508, 106, 1'b0, 1'b0);
        check("pong: bricks untouched", bricks, BRICKS_FULL);
    endtask

    task automatic test_brick_hits();
        $display("--- test_brick_hits");
        mode = 1'b1;
        do_reset();
        // Head-on into the front face (x = 512) of column 0, row 3 (y = 96..127).
        set_ball(500, 100, 1'b0, 1'b0);
        tick(1);  check_ball("brick: approach", 504, 103, 1'b0, 1'b0);
        check("brick: wall still full", bricks, BRICKS_FULL);
        tick(1);  check_ball("brick: front-face hit", 504, 103, 1'b1, 1'b0);
        check("brick: {col 0,row 3} removed", bricks, BRICKS_FULL & ~(32'd1 << 3));
        tick(1);  check_ball("brick: flies back", 500, 106, 1'b1, 1'b0);
        // Same path again: the hole lets the ball into the wall...
        set_ball(500, 100, 1'b0, 1'b0);
        tick(2);  check_ball("brick: enters the hole", 508, 106, 1'b0, 1'b0);
        tick(5);  check_ball("brick: inside the hole", 528, 121, 1'b0, 1'b0);
        // ...where it meets row 4 from above: a horizontal face flips vy.
        tick(1);  check_ball("brick: top-face hit", 528, 121, 1'b0, 1'b1);
        check("brick: {col 0,row 4} removed", bricks, BRICKS_FULL & ~(32'd1 << 3) & ~(32'd1 << 4));
        check("brick: hits are not misses", score_r, 0);
        // Column 1 from behind (moving left from the gap at the right edge).
        set_ball(580, 200, 1'b1, 1'b0);
        tick(1);  check_ball("brick: back-face approach", 576, 203, 1'b1, 1'b0);
        tick(1);  check_ball("brick: back-face hit", 576, 203, 1'b0, 1'b0);
        check("brick: {col 1,row 6} removed",
              bricks, BRICKS_FULL & ~(32'd1 << 3) & ~(32'd1 << 4) & ~(32'd1 << 22));
    endtask

    task automatic test_brick_walls();
        $display("--- test_brick_walls");
        mode = 1'b1;
        do_reset();
        @(negedge clk); dut.bricks_q = 32'd1;       // only {col 0,row 0} left
        // The right edge is a wall, not a goal.
        set_ball(624, 200, 1'b0, 1'b0);
        tick(1);  check_ball("brick: near right wall", 628, 203, 1'b0, 1'b0);
        tick(1);  check_ball("brick: right wall bounce", 632, 206, 1'b1, 1'b0);
        tick(1);  check_ball("brick: after right wall", 628, 209, 1'b1, 1'b0);
        check("brick: no point at right wall", score_l, 0);
        // There is no right paddle in this mode.
        set_ball(604, 236, 1'b0, 1'b0);
        tick(1);  check_ball("brick: no right paddle", 608, 239, 1'b0, 1'b0);
        // The left paddle still works.
        set_ball(28, 236, 1'b1, 1'b0);
        tick(1);  check_ball("brick: left paddle hit", 24, 239, 1'b0, 1'b0);
    endtask

    task automatic test_brick_miss_and_game_over();
        $display("--- test_brick_miss_and_game_over");
        mode = 1'b1;
        do_reset();
        set_ball(4, 100, 1'b1, 1'b1);
        tick(1);  check("brick: no miss yet", score_r, 0);
        tick(1);
        check("brick: miss counted", score_r, 1);
        check("brick: score_l unused", score_l, 0);
        check("brick: re-serve ball_x", ball_x, 316);
        check("brick: re-serve ball_y", ball_y, 236);
        check("brick: wall kept after miss", bricks, BRICKS_FULL);
        @(negedge clk); dut.score_r_q = 3'd2;
        set_ball(0, 100, 1'b1, 1'b1);
        tick(1);
        check("brick: third miss", score_r, 3);
        tick(10);
        check("brick: game over ball_x", ball_x, 316);
        check("brick: game over ball_y", ball_y, 236);
        check("brick: misses stay 3", score_r, 3);
        do_reset();
        check("brick: reset clears misses", score_r, 0);
    endtask

    task automatic test_brick_win();
        $display("--- test_brick_win");
        mode = 1'b1;
        do_reset();
        @(negedge clk); dut.bricks_q = 32'd1 << 3;  // one brick left
        set_ball(500, 100, 1'b0, 1'b0);
        tick(2);
        check("brick: last brick removed", bricks, 0);
        tick(10);
        check("brick: win freezes ball_x", ball_x, 504);
        check("brick: win freezes ball_y", ball_y, 103);
        check("brick: win without misses", score_r, 0);
        do_reset();
        check("brick: reset rebuilds wall", bricks, BRICKS_FULL);
    endtask

    // The paddle tracks the ball through its buttons: bricks must keep
    // disappearing, the ball must never be missed and never leave the field.
    task automatic test_brick_autoplay();
        int out_of_field;
        int frames;
        $display("--- test_brick_autoplay");
        mode = 1'b1;
        do_reset();
        out_of_field = 0;
        frames       = 0;
        while (frames < 6000 && bricks != 32'd0) begin
            btn = 4'b0000;
            if      (ball_y + 4 < p1_y + 28) btn = P1_UP;
            else if (ball_y + 4 > p1_y + 36) btn = P1_DOWN;
            tick(1);
            frames++;
            if (ball_x > 632 || ball_y > 472 || p1_y > 416) out_of_field++;
        end
        btn = 4'b0000;
        $display("       autoplay: %0d bricks left after %0d frames", count_bricks(), frames);
        check("brick autoplay: no misses", score_r, 0);
        check("brick autoplay: at least 10 bricks broken", count_bricks() <= 20, 1);
        check("brick autoplay: nothing left the field", out_of_field, 0);
        check("brick autoplay: only real bricks", bricks & ~BRICKS_FULL, 0);
        mode = 1'b0;
    endtask

    initial begin
        test_reset();
        test_paddle_move();
        test_paddle_clamp();
        test_ball_motion();
        test_ball_bounce_wall();
        test_ball_bounce_paddle();
        test_score_and_serve();
        test_game_over();
        test_lfsr();
        test_first_point();
        test_rally();
        test_pong_ignores_bricks();
        test_brick_reset();
        test_brick_hits();
        test_brick_walls();
        test_brick_miss_and_game_over();
        test_brick_win();
        test_brick_autoplay();
        $display("TESTBENCH_SUMMARY: %0d PASS, %0d FAIL", pass_count, fail_count);
        $display("TESTBENCH_RESULT: %s", (fail_count == 0) ? "PASS" : "FAIL");
        $finish;
    end

    // Watchdog: a hung sim must not look like a pass.
    initial begin
        #(50_000_000);
        $display("TESTBENCH_RESULT: FAIL (timeout)");
        $finish;
    end

endmodule
