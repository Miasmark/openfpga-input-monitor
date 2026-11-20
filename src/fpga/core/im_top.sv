// Input monitor: the controller words on screen, and what they decode to.
//
// clk_74a side (the domain the APF pad controller writes the words in):
// - every controller's raw words, and how often each changes (changes per
//   second, BCD);
// - the mouse, read as the Atari ST core's notes describe it (controller 4,
//   type 5): a report counter in key[15:0], X in joy[15:0], Y in trig[15:0],
//   buttons in joy[18:16]. Each time the counter changes, X and Y are taken
//   as one report's motion, half a poll later (the pad controller writes
//   key, joy and trig one after another, once every 882 us), and added to
//   the sums and to a pointer. Wrong guesses show plainly: the pointer runs
//   off or does not follow;
// - the keyboard (controller 3, type 4): six HID codes in joy[31:0] and
//   trig[15:0]; each new code is a press, echoed as text, and both bytes
//   that may hold the modifiers (key[7:0], key[15:8]) are shown bit by bit.
// clk_pix side: 320 x 240 video, 40 x 30 cells of 8 x 8 (tools/gen_screen.py).
// The video reads a snapshot of the clk_74a values, refreshed only in a
// window in the vertical blank (snap_win), so it never reads them while
// they change.

`default_nettype none

module im_top (
    input  wire        clk_74a,
    input  wire        clk_pix,

    input  wire [31:0] cont1_key, cont2_key, cont3_key, cont4_key,
    input  wire [31:0] cont1_joy, cont2_joy, cont3_joy, cont4_joy,
    input  wire [15:0] cont1_trig, cont2_trig, cont3_trig, cont4_trig,
    input  wire        clear_74a,           // a pulse: clear the sums (the menu's action)

    output logic [23:0] video_rgb,
    output logic        video_de,
    output logic        video_hs,
    output logic        video_vs
);

    // ------------------------------------------------------------------
    // clk_74a: the live values
    // ------------------------------------------------------------------
    logic [31:0] key [4], joy [4];
    logic [15:0] trig [4];
    always_comb begin
        key[0] = cont1_key;   key[1] = cont2_key;   key[2] = cont3_key;   key[3] = cont4_key;
        joy[0] = cont1_joy;   joy[1] = cont2_joy;   joy[2] = cont3_joy;   joy[3] = cont4_joy;
        trig[0] = cont1_trig; trig[1] = cont2_trig; trig[2] = cont3_trig; trig[3] = cont4_trig;
    end

    function automatic logic [11:0] bcd_inc(input logic [11:0] v);
        logic [11:0] r;
        r = v;
        if (r != 12'h999) begin
            if (r[3:0] != 4'd9) r[3:0] = r[3:0] + 4'd1;
            else begin
                r[3:0] = 4'd0;
                if (r[7:4] != 4'd9) r[7:4] = r[7:4] + 4'd1;
                else begin
                    r[7:4] = 4'd0;
                    r[11:8] = r[11:8] + 4'd1;
                end
            end
        end
        bcd_inc = r;
    endfunction

    // the clear: the menu's action, or Select on player 1
    logic sel_d = 1'b0;
    always_ff @(posedge clk_74a) sel_d <= cont1_key[14];
    wire clear = clear_74a | (cont1_key[14] & ~sel_d);

    // changes per second, per controller
    localparam int SEC = 74_250_000;
    logic [26:0] sec_cnt = '0;
    logic [79:0] prev_word [4];
    logic [11:0] chg [4];
    logic [11:0] rate [4];
    initial for (int i = 0; i < 4; i++) begin prev_word[i] = '0; chg[i] = '0; rate[i] = '0; end
    wire sec_tick = sec_cnt == SEC - 1;
    always_ff @(posedge clk_74a) begin
        sec_cnt <= sec_tick ? '0 : sec_cnt + 27'd1;
        for (int i = 0; i < 4; i++) begin : rate_i
            logic [79:0] w;
            logic [11:0] c;
            w = {key[i], joy[i], trig[i]};
            c = chg[i];
            if (w != prev_word[i]) c = bcd_inc(c);
            prev_word[i] <= w;
            if (sec_tick) begin
                rate[i] <= c;
                chg[i]  <= '0;
            end else
                chg[i] <= c;
        end
    end

    // the mouse
    logic [15:0] mcnt_prev = '0;
    logic        m_pend = 1'b0;
    logic [14:0] m_dly = '0;                // 2^15 / 74.25 MHz = 441 us
    logic [15:0] sumx = '0, sumy = '0, ldx = '0, ldy = '0, reports = '0, skips = '0;
    logic [8:0]  px = 9'd160;
    logic [7:0]  py = 8'd120;

    function automatic logic [8:0] clampx(input logic [8:0] p, input logic [15:0] d);
        logic signed [17:0] t;
        t = $signed({9'd0, p}) + $signed({{2{d[15]}}, d});
        if (t < 0)        clampx = 9'd0;
        else if (t > 319) clampx = 9'd319;
        else              clampx = t[8:0];
    endfunction
    function automatic logic [7:0] clampy(input logic [7:0] p, input logic [15:0] d);
        logic signed [17:0] t;
        t = $signed({10'd0, p}) + $signed({{2{d[15]}}, d});
        if (t < 0)        clampy = 8'd0;
        else if (t > 239) clampy = 8'd239;
        else              clampy = t[7:0];
    endfunction

    always_ff @(posedge clk_74a) begin
        if (cont4_key[15:0] != mcnt_prev) begin
            mcnt_prev <= cont4_key[15:0];
            if (cont4_key[15:0] != mcnt_prev + 16'd1) skips <= skips + 16'd1;
            m_pend <= 1'b1;
            m_dly  <= '0;
        end else if (m_pend) begin
            m_dly <= m_dly + 15'd1;
            if (&m_dly) begin
                m_pend  <= 1'b0;
                sumx    <= sumx + cont4_joy[15:0];
                sumy    <= sumy + cont4_trig;
                reports <= reports + 16'd1;
                if (cont4_joy[15:0] != 0) ldx <= cont4_joy[15:0];
                if (cont4_trig != 0)      ldy <= cont4_trig;
                px <= clampx(px, cont4_joy[15:0]);
                py <= clampy(py, cont4_trig);
            end
        end
        if (clear) begin
            sumx <= '0; sumy <= '0; ldx <= '0; ldy <= '0; reports <= '0; skips <= '0;
            px <= 9'd160; py <= 8'd120;
        end
    end

    // the keyboard
    function automatic logic [6:0] hid_ascii(input logic [7:0] c);
        if (c >= 8'h04 && c <= 8'h1D)      hid_ascii = 7'(8'h41 + c - 8'h04);   // A-Z
        else if (c >= 8'h1E && c <= 8'h26) hid_ascii = 7'(8'h31 + c - 8'h1E);   // 1-9
        else if (c >= 8'h59 && c <= 8'h61) hid_ascii = 7'(8'h31 + c - 8'h59);   // keypad 1-9
        else case (c)
            8'h27, 8'h62: hid_ascii = 7'h30;    // 0
            8'h2B, 8'h2C: hid_ascii = 7'h20;    // Tab, space
            8'h2D, 8'h56: hid_ascii = 7'h2D;    // -
            8'h2E: hid_ascii = 7'h3D;           // =
            8'h2F: hid_ascii = 7'h5B;           // [
            8'h30: hid_ascii = 7'h5D;           // ]
            8'h33: hid_ascii = 7'h3B;           // ;
            8'h34: hid_ascii = 7'h27;           // '
            8'h36: hid_ascii = 7'h2C;           // ,
            8'h37, 8'h63: hid_ascii = 7'h2E;    // .
            8'h38, 8'h54: hid_ascii = 7'h2F;    // /
            8'h57: hid_ascii = 7'h2B;           // keypad +
            8'h55: hid_ascii = 7'h23;           // keypad * (shown as #)
            default: hid_ascii = 7'h3F;         // ?
        endcase
    endfunction

    wire        kbd = cont3_key[31:28] == 4'd4;
    wire  [5:0][7:0] codes_now = {cont3_trig, cont3_joy};   // code i = bits [8i+7:8i]
    logic [5:0][7:0] codes = '0;
    logic [5:0][7:0] prev = '0;
    logic       k_busy = 1'b0;
    logic [2:0] k_step = '0;
    logic [7:0] last = '0;
    logic [15:0] presses = '0;
    logic [6:0] typed [40];
    logic [5:0] tpos = '0;
    initial for (int i = 0; i < 40; i++) typed[i] = 7'h20;

    logic [7:0] kc;
    logic       k_new;
    always_comb begin
        kc = codes[k_step];
        k_new = kc >= 8'h04;
        for (int i = 0; i < 6; i++) if (prev[i] == kc) k_new = 1'b0;
    end

    always_ff @(posedge clk_74a) begin
        if (!k_busy) begin
            if (kbd && codes_now != codes) begin
                codes  <= codes_now;
                k_busy <= 1'b1;
                k_step <= '0;
            end
        end else begin
            if (k_new) begin
                last    <= kc;
                presses <= presses + 16'd1;
                if (kc == 8'h28 || kc == 8'h58) begin           // Enter: a new line
                    for (int i = 0; i < 40; i++) typed[i] <= 7'h20;
                    tpos <= '0;
                end else if (kc == 8'h2A) begin                 // Backspace
                    if (tpos != 0) begin
                        typed[tpos - 6'd1] <= 7'h20;
                        tpos <= tpos - 6'd1;
                    end
                end else if (tpos == 6'd40) begin               // full: start again
                    for (int i = 1; i < 40; i++) typed[i] <= 7'h20;
                    typed[0] <= hid_ascii(kc);
                    tpos <= 6'd1;
                end else begin
                    typed[tpos] <= hid_ascii(kc);
                    tpos <= tpos + 6'd1;
                end
            end
            k_step <= k_step + 3'd1;
            if (k_step == 3'd5) begin
                prev   <= codes;
                k_busy <= 1'b0;
            end
        end
        if (clear) begin
            last <= '0;
            presses <= '0;
            for (int i = 0; i < 40; i++) typed[i] <= 7'h20;
            tpos <= '0;
        end
    end

    // ------------------------------------------------------------------
    // The snapshot (clk_74a), refreshed only while the video is in its
    // window in the vertical blank
    // ------------------------------------------------------------------
    logic snap_win;                         // clk_pix
    logic [2:0] snap_s = '0;
    always_ff @(posedge clk_74a) snap_s <= {snap_s[1:0], snap_win};

    logic [31:0] s_key [4], s_joy [4];
    logic [15:0] s_trig [4];
    logic [11:0] s_rate [4];
    logic [15:0] s_sumx, s_sumy, s_ldx, s_ldy, s_reports, s_skips, s_presses;
    logic [8:0]  s_px;
    logic [7:0]  s_py, s_last;
    logic [6:0]  s_typed [40];
    always_ff @(posedge clk_74a) if (snap_s[2]) begin
        for (int i = 0; i < 4; i++) begin
            s_key[i] <= key[i]; s_joy[i] <= joy[i]; s_trig[i] <= trig[i]; s_rate[i] <= rate[i];
        end
        s_sumx <= sumx; s_sumy <= sumy; s_ldx <= ldx; s_ldy <= ldy;
        s_reports <= reports; s_skips <= skips; s_presses <= presses;
        s_px <= px; s_py <= py; s_last <= last;
        for (int i = 0; i < 40; i++) s_typed[i] <= typed[i];
    end

    // ------------------------------------------------------------------
    // clk_pix: 320 x 240 out of 400 x 262 (6.1875 MHz: 59.04 Hz)
    // ------------------------------------------------------------------
    localparam int H_TOTAL = 400, H_START = 40, H_ACTIVE = 320;
    localparam int V_TOTAL = 262, V_START = 16, V_ACTIVE = 240;

    logic [8:0] hc = '0, vc = '0;
    always_ff @(posedge clk_pix) begin
        if (hc == H_TOTAL - 1) begin
            hc <= '0;
            vc <= vc == V_TOTAL - 1 ? 9'd0 : vc + 9'd1;
        end else
            hc <= hc + 9'd1;
    end
    // four lines in the front porch, a full line clear of the active picture
    assign snap_win = vc >= 9'd257 && vc <= 9'd260;

    `include "screen_rom.svh"
    `include "font_rom.svh"

    wire        act = hc >= H_START && hc < H_START + H_ACTIVE && vc >= V_START && vc < V_START + V_ACTIVE;
    wire [8:0]  ax = hc - 9'(H_START);
    wire [8:0]  ay = vc - 9'(V_START);
    wire [10:0] code = screen_code(ay[7:3], ax[8:3]);

    logic [6:0] ch;
    always_comb begin
        unique case (code[9:8])
            2'd0: ch = code[6:0];
            2'd1: begin : hexd
                logic [3:0] n;
                n = nib[code[7:0]];
                ch = n < 4'd10 ? 7'(8'h30 + n) : 7'(8'h41 + n - 4'd10);
            end
            2'd2: ch = bitf[code[7:0]] ? 7'h31 : 7'h2E;
            default: ch = s_typed[code[5:0]];
        endcase
    end
    wire [7:0] glyph = font_row(ch, ay[2:0]);
    wire       ink   = glyph[3'd7 - ax[2:0]];

    wire signed [10:0] dxp = $signed({2'b0, ax}) - $signed({2'b0, s_px});
    wire signed [10:0] dyp = $signed({2'b0, ay}) - $signed({3'b0, s_py});
    wire       ptr = dxp >= -2 && dxp <= 2 && dyp >= -2 && dyp <= 2;

    localparam [23:0] C_BG = 24'h101838, C_FG = 24'hD8D8D8, C_HI = 24'hF0C040, C_PTR = 24'hFF3030;

    always_ff @(posedge clk_pix) begin
        video_vs <= hc == 9'd0 && vc == 9'd0;
        video_hs <= hc == 9'd3;
        video_de <= act;
        if (!act)
            video_rgb <= 24'd0;
        else if (ptr)
            video_rgb <= C_PTR;
        else if (ink)
            video_rgb <= code[10] ? C_HI : C_FG;
        else
            video_rgb <= C_BG;
    end

endmodule

`default_nettype wire
