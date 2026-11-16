// Shared constants for the Pong design. `include this file inside a module
// body (after the port list); it only contains localparams.
// All positions are in pixels, origin top-left.

// ---- VGA timing: 640x480 @ 60 Hz, 25 MHz pixel clock ----
localparam [9:0] H_VISIBLE    = 10'd640;
localparam [9:0] H_SYNC_START = 10'd656;   // visible + front porch
localparam [9:0] H_SYNC_END   = 10'd752;   // + sync width (96)
localparam [9:0] H_TOTAL      = 10'd800;

localparam [9:0] V_VISIBLE    = 10'd480;
localparam [9:0] V_SYNC_START = 10'd490;   // visible + front porch
localparam [9:0] V_SYNC_END   = 10'd492;   // + sync width (2)
localparam [9:0] V_TOTAL      = 10'd525;

// ---- Paddles ----
localparam [9:0] PADDLE_W       = 10'd8;
localparam [9:0] PADDLE_H       = 10'd64;
localparam [9:0] PADDLE_L_X     = 10'd16;
localparam [9:0] PADDLE_R_X     = 10'd616;
localparam [9:0] PADDLE_SPEED   = 10'd4;
localparam [9:0] PADDLE_Y_MAX   = V_VISIBLE - PADDLE_H;          // 416
localparam [9:0] PADDLE_Y_START = (V_VISIBLE - PADDLE_H) >> 1;   // 208

// ---- Ball ----
localparam [9:0] BALL_SIZE    = 10'd8;
localparam [9:0] BALL_HALF    = 10'd4;
localparam [9:0] BALL_VX      = 10'd4;
localparam [9:0] BALL_VY      = 10'd3;
localparam [9:0] BALL_X_MAX   = H_VISIBLE - BALL_SIZE;           // 632
localparam [9:0] BALL_Y_MAX   = V_VISIBLE - BALL_SIZE;           // 472
localparam [9:0] BALL_X_START = (H_VISIBLE - BALL_SIZE) >> 1;    // 316
localparam [9:0] BALL_Y_START = (V_VISIBLE - BALL_SIZE) >> 1;    // 236

// ball_x at which the ball touches the face of each paddle
localparam [9:0] BALL_X_HIT_L = PADDLE_L_X + PADDLE_W;           // 24
localparam [9:0] BALL_X_HIT_R = PADDLE_R_X - BALL_SIZE;          // 608

// Hit zones: ball centre relative to paddle top. < ZONE_UPPER deflects up,
// >= ZONE_LOWER deflects down, in between keeps the current direction.
localparam [9:0] ZONE_UPPER   = 10'd21;
localparam [9:0] ZONE_LOWER   = 10'd43;

// ---- Score ----
localparam [2:0] SCORE_MAX    = 3'd7;
localparam [3:0] LFSR_SEED    = 4'b1001;

// ---- Rendering ----
localparam [9:0] NET_X        = 10'd319;   // 2 px wide: x = 319, 320
localparam [9:0] NET_W        = 10'd2;

// Score boxes sit on an 8 px grid: cell = h_cnt[9:3], row = v_cnt[9:3].
localparam [6:0] SCORE_ROW    = 7'd1;      // y = 8..15
localparam [6:0] SCORE_L_COL  = 7'd30;     // x = 240
localparam [6:0] SCORE_R_COL  = 7'd49;     // x = 392
localparam [2:0] SCORE_BOX_W  = 3'd6;      // lit pixels per 8 px cell

// Colors: {R[1:0], G[1:0], B[1:0]}
localparam [5:0] COLOR_BLACK  = 6'b00_00_00;
localparam [5:0] COLOR_WHITE  = 6'b11_11_11;
localparam [5:0] COLOR_YELLOW = 6'b11_11_00;
localparam [5:0] COLOR_GREY   = 6'b01_01_01;
localparam [5:0] COLOR_GREEN  = 6'b00_11_00;
localparam [5:0] COLOR_RED    = 6'b11_00_00;
