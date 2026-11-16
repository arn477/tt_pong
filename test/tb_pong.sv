`default_nettype none
`timescale 1ns / 1ps

// Top-level testbench for tt_um_pong: VGA timing, reset state, buttons through
// the synchronizer, and rendering. Every output pixel of every simulated frame
// is compared against an independent reference model written from the numbers
// in docs/info.md. Game rules are covered in depth by tb_pong_game.sv.
module tb_pong;

    logic       clk = 1'b0;
    logic       rst_n = 1'b0;
    logic [7:0] ui_in = 8'd0;
    logic [7:0] uio_in = 8'd0;
    wire  [7:0] uo_out;
    wire  [7:0] uio_out;
    wire  [7:0] uio_oe;

    tt_um_pong dut (
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),
        .ena     (1'b1),
        .clk     (clk),
        .rst_n   (rst_n)
    );

    always #20 clk = ~clk;      // 25 MHz

    // Tiny VGA PMOD pinout
    wire       hsync = uo_out[7];
    wire       vsync = uo_out[3];
    wire [5:0] rgb   = {uo_out[0], uo_out[4], uo_out[1], uo_out[5], uo_out[2], uo_out[6]};  // {R,G,B}

    localparam logic [5:0] BLACK  = 6'b00_00_00;
    localparam logic [5:0] WHITE  = 6'b11_11_11;
    localparam logic [5:0] YELLOW = 6'b11_11_00;
    localparam logic [5:0] GREY   = 6'b01_01_01;
    localparam logic [5:0] GREEN  = 6'b00_11_00;
    localparam logic [5:0] RED    = 6'b11_00_00;

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

    // ---------------- reference model + full-frame monitor ----------------
    // Expected pin values for beam position (h, v) and the given game state.
    function automatic logic [7:0] model_pins(input int h, input int v,
                                              input int p1, input int p2,
                                              input int bx, input int by,
                                              input int sl, input int sr);
        logic [5:0] c;
        logic       hs, vs;
        c = BLACK;
        if (h < 640 && v < 480) begin
            if (h >= bx && h < bx + 8 && v >= by && v < by + 8)
                c = YELLOW;
            else if (h >= 16 && h < 24 && v >= p1 && v < p1 + 64)
                c = WHITE;
            else if (h >= 616 && h < 624 && v >= p2 && v < p2 + 64)
                c = WHITE;
            else if (v >= 8 && v < 16 && h >= 240 && h < 240 + 8 * sl && ((h - 240) % 8) < 6)
                c = GREEN;
            else if (v >= 8 && v < 16 && h >= 392 && h < 392 + 8 * sr && ((h - 392) % 8) < 6)
                c = RED;
            else if ((h == 319 || h == 320) && ((v / 16) % 2) == 1)
                c = GREY;
        end
        hs = !(h >= 656 && h < 752);
        vs = !(v >= 490 && v < 492);
        return {hs, c[0], c[2], c[4], vs, c[1], c[3], c[5]};
    endfunction

    logic [7:0] exp_q;
    logic       exp_valid = 1'b0;
    int         mismatches = 0;
    int         n_white, n_yellow, n_grey, n_green, n_red, n_other;

    // The DUT registers its outputs, so the pins seen before a clock edge
    // belong to the beam position/state sampled one edge earlier.
    always @(posedge clk) begin
        if (!rst_n) begin
            exp_valid <= 1'b0;
        end else begin
            if (exp_valid) begin
                if (uo_out !== exp_q) begin
                    mismatches++;
                    if (mismatches <= 10)
                        $display("[FAIL] pin mismatch at t=%0t: uo_out=%b expected %b", $time, uo_out, exp_q);
                end
                case (rgb)
                    BLACK:   ;
                    WHITE:   n_white++;
                    YELLOW:  n_yellow++;
                    GREY:    n_grey++;
                    GREEN:   n_green++;
                    RED:     n_red++;
                    default: n_other++;
                endcase
            end
            exp_q     <= model_pins(dut.h_cnt, dut.v_cnt, dut.game.p1_y_q, dut.game.p2_y_q,
                                    dut.game.ball_x_q, dut.game.ball_y_q,
                                    dut.game.score_l_q, dut.game.score_r_q);
            exp_valid <= 1'b1;
        end
    end

    task automatic clear_color_counts();
        n_white = 0; n_yellow = 0; n_grey = 0; n_green = 0; n_red = 0; n_other = 0;
    endtask

    // ---------------- helpers ----------------
    task automatic do_reset();
        ui_in = 8'd0;
        rst_n = 1'b0;
        repeat (5) @(negedge clk);
        rst_n = 1'b1;
    endtask

    // Wait for n game updates. Returns on the negedge right after the update.
    task automatic wait_frames(input int n);
        repeat (n) begin
            @(negedge clk);
            while (!dut.frame_tick) @(negedge clk);
            @(negedge clk);
        end
    endtask

    // Check the color driven for pixel (x, y) the next time the beam gets there
    // (which may be right now: consecutive pixels can be sampled back to back).
    task automatic sample_pixel(input string name, input int x, input int y, input logic [5:0] expected);
        while (!(dut.h_cnt == x && dut.v_cnt == y)) @(negedge clk);
        @(negedge clk);         // output register now holds pixel (x, y)
        check(name, rgb, expected);
    endtask

    // ---------------- scenarios ----------------
    task automatic test_reset();
        $display("--- test_reset");
        rst_n = 1'b0;
        repeat (5) @(negedge clk);
        check("in reset: hsync high", hsync, 1);
        check("in reset: vsync high", vsync, 1);
        check("in reset: rgb black", rgb, BLACK);
        rst_n = 1'b1;
        @(negedge clk);
        check("reset p1_y", dut.game.p1_y_q, 208);
        check("reset p2_y", dut.game.p2_y_q, 208);
        check("reset ball_x", dut.game.ball_x_q, 316);
        check("reset ball_y", dut.game.ball_y_q, 236);
        check("reset score_l", dut.game.score_l_q, 0);
        check("reset score_r", dut.game.score_r_q, 0);
        check("uio_oe all inputs", uio_oe, 0);
        check("uio_out zero", uio_out, 0);
    endtask

    task automatic test_vga_timing();
        int t_fall, t_rise, t_fall2;
        int cyc;
        $display("--- test_vga_timing");
        cyc = 0;
        // hsync: low pulse width and period, in clocks
        while (!hsync) begin @(negedge clk); cyc++; end
        while ( hsync) begin @(negedge clk); cyc++; end
        t_fall = cyc;
        while (!hsync) begin @(negedge clk); cyc++; end
        t_rise = cyc;
        while ( hsync) begin @(negedge clk); cyc++; end
        t_fall2 = cyc;
        check("hsync pulse width (clocks)", t_rise - t_fall, 96);
        check("hsync period (clocks)", t_fall2 - t_fall, 800);
        // vsync: low pulse width and period, in clocks (lines x 800)
        while (!vsync) begin @(negedge clk); cyc++; end
        while ( vsync) begin @(negedge clk); cyc++; end
        t_fall = cyc;
        while (!vsync) begin @(negedge clk); cyc++; end
        t_rise = cyc;
        while ( vsync) begin @(negedge clk); cyc++; end
        t_fall2 = cyc;
        check("vsync pulse width (clocks)", t_rise - t_fall, 2 * 800);
        check("vsync period (clocks)", t_fall2 - t_fall, 525 * 800);
    endtask

    task automatic test_paddles();
        $display("--- test_paddles");
        do_reset();
        wait_frames(1);
        ui_in = 8'b0000_0001;   wait_frames(3);     // P1 up
        check("p1 up x3", dut.game.p1_y_q, 196);
        check("p2 unaffected", dut.game.p2_y_q, 208);
        ui_in = 8'b0000_1010;   wait_frames(2);     // P1 down + P2 down
        check("p1 down x2", dut.game.p1_y_q, 204);
        check("p2 down x2", dut.game.p2_y_q, 216);
        ui_in = 8'b0000_0111;   wait_frames(2);     // P1 up+down, P2 up
        check("p1 up+down holds", dut.game.p1_y_q, 204);
        check("p2 up x2", dut.game.p2_y_q, 208);
        ui_in = 8'b1111_0000;   wait_frames(2);     // unused inputs do nothing
        check("ui[7:4] ignored (p1)", dut.game.p1_y_q, 204);
        check("ui[7:4] ignored (p2)", dut.game.p2_y_q, 208);
        ui_in = 8'd0;
        // 1 (reset) + 9 frames of ball motion at +4/+3 per frame
        check("ball_x after 10 frames", dut.game.ball_x_q, 316 + 4 * 10);
        check("ball_y after 10 frames", dut.game.ball_y_q, 236 + 3 * 10);
    endtask

    task automatic test_render_pixels();
        int bx, by;
        $display("--- test_render_pixels");
        do_reset();
        wait_frames(1);
        // Set up a scene with every object visible (during vertical blanking).
        dut.game.score_l_q = 3'd3;
        dut.game.score_r_q = 3'd5;
        dut.game.ball_x_q  = 10'd100;
        dut.game.ball_y_q  = 10'd300;
        dut.game.p1_y_q    = 10'd40;
        dut.game.p2_y_q    = 10'd400;
        wait_frames(1);

        // Count colored pixels over exactly one frame.
        clear_color_counts();
        wait_frames(1);
        check("white pixels (2 paddles 8x64)", n_white, 2 * 8 * 64);
        check("yellow pixels (ball 8x8)", n_yellow, 64);
        check("green pixels (3 boxes 6x8)", n_green, 3 * 6 * 8);
        check("red pixels (5 boxes 6x8)", n_red, 5 * 6 * 8);
        check("grey pixels (net 2x240)", n_grey, 2 * 240);
        check("no other colors", n_other, 0);

        // Spot checks. The ball moves once per frame, so sample it first.
        bx = dut.game.ball_x_q;
        by = dut.game.ball_y_q;
        sample_pixel("ball top-left",          bx,      by,      YELLOW);
        sample_pixel("ball bottom-right",      bx + 7,  by + 7,  YELLOW);
        sample_pixel("right of ball",          bx + 8,  by + 7,  BLACK);
        wait_frames(1);
        sample_pixel("background",             100,     100,     BLACK);
        sample_pixel("score L box 0",          240,     8,       GREEN);
        sample_pixel("score L box gap",        246,     8,       BLACK);
        sample_pixel("score L box 2",          261,     15,      GREEN);
        sample_pixel("score L box 3 (unlit)",  264,     15,      BLACK);
        sample_pixel("score R box 0",          392,     8,       RED);
        sample_pixel("score R box 4",          429,     15,      RED);
        sample_pixel("score R box 5 (unlit)",  432,     15,      BLACK);
        sample_pixel("below score row",        240,     16,      BLACK);
        sample_pixel("net dash",               319,     16,      GREY);
        sample_pixel("net dash 2nd column",    320,     31,      GREY);
        sample_pixel("beside net",             321,     31,      BLACK);
        sample_pixel("net gap",                319,     32,      BLACK);
        sample_pixel("p1 paddle top-left",     16,      40,      WHITE);
        sample_pixel("p1 paddle bottom-right", 23,      103,     WHITE);
        sample_pixel("below p1 paddle",        23,      104,     BLACK);
        sample_pixel("p2 paddle top-left",     616,     400,     WHITE);
        sample_pixel("p2 paddle bottom-right", 623,     463,     WHITE);
        sample_pixel("right of p2 paddle",     624,     463,     BLACK);
        sample_pixel("h blanking",             700,     450,     BLACK);
        sample_pixel("v blanking",             18,      500,     BLACK);
    endtask

    initial begin
        clear_color_counts();
        test_reset();
        test_vga_timing();
        test_paddles();
        test_render_pixels();
        check("pin mismatches vs reference model", mismatches, 0);
        $display("TESTBENCH_SUMMARY: %0d PASS, %0d FAIL", pass_count, fail_count);
        $display("TESTBENCH_RESULT: %s", (fail_count == 0) ? "PASS" : "FAIL");
        $finish;
    end

    // Watchdog: a hung sim must not look like a pass. One frame = 16.8 ms.
    initial begin
        #(1_000_000_000);
        $display("TESTBENCH_RESULT: FAIL (timeout)");
        $finish;
    end

endmodule
