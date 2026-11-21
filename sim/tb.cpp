// Input monitor simulation: drives im_top with made-up controller words
// (a pad, a keyboard typing, a mouse moving right and down with its left
// button held) and writes the last whole frame to sim/work/frame.ppm.
#include "Vim_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <vector>

static const int W = 320, H = 240;

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vim_top *t = new Vim_top;
    double secs = argc > 1 ? atof(argv[1]) : 1.2;
    const uint64_t cycles = (uint64_t)(secs * 74250000.0);
    const uint64_t poll = 65488;        // 882 us at 74.25 MHz
    std::vector<uint32_t> fb(W * H), last(W * H);
    int x = 0, y = 0, frames = 0;
    bool in_frame = false;
    uint16_t mcnt = 0;
    // keyboard script: one entry per 20 ms, six codes each
    const uint8_t keys[][6] = {
        {0x0B}, {}, {0x0C}, {}, {0x2C}, {}, {0x13}, {}, {0x12}, {0x12, 0x0C}, {0x0C},
        {}, {0x0C, 0x1A}, {}, {0x1F}, {},
    };
    const int nkeys = sizeof(keys) / sizeof(keys[0]);
    t->cont1_key = 0x10000000;           // a Pocket pad: type 1
    t->cont1_joy = 0x80808080;
    t->cont2_key = 0;
    for (uint64_t c = 0; c < cycles; c++) {
        // the pad controller's poll: cont3, then cont4, words one by one
        uint64_t ph = c % poll;
        uint64_t n = c / poll;
        if (ph == 100) {
            int ki = (int)((c / 1485000) % (nkeys + 8));     // 20 ms per step, then a pause
            uint32_t j = 0, tr = 0;
            if (ki < nkeys) {
                const uint8_t *k = keys[ki];
                j = k[0] | k[1] << 8 | k[2] << 16 | k[3] << 24;
                tr = k[4] | k[5] << 8;
            }
            uint32_t mod = (c > 37125000 && c < 44550000) ? 0x02 : 0;   // left Shift, 0.5-0.6 s
            t->cont3_key = 0x40000000 | mod << 8 | (n & 0xFF);          // modifier byte at [15:8] in this script
            t->cont3_joy = j;
            t->cont3_trig = tr;
        }
        if (ph == 2000 && (n % 2) == 0) {   // a 500 Hz mouse: a report every other poll
            mcnt++;
            t->cont4_key = 0x50000000 | mcnt;
        }
        if (ph == 3000) {
            bool moving = (n % 2) == 0;
            int16_t dx = moving ? 2 : 0, dy = moving ? (c > 30000000 ? -1 : 0) : 0;
            // as the Dock sends them: each count's low byte in [15:8]; buttons in [20:16]; wheel [31:24]
            auto sw = [](int16_t v) { return (uint16_t)(((uint16_t)v << 8) | ((uint16_t)v >> 8)); };
            t->cont4_joy = (1u << 16) | (c > 50000000 ? 0x01000000u : 0) | sw(dx);
            t->cont4_trig = sw(dy);
        }
        t->clear_74a = 0;
        t->clk_74a = 1;
        if (c % 12 == 0) t->clk_pix = 1;
        t->eval();
        if (c % 12 == 0) {
            if (t->video_vs) {
                if (in_frame && y >= H) { last = fb; frames++; }
                in_frame = true; y = -1;
            }
            if (t->video_hs) { y++; x = 0; }
            if (t->video_de && in_frame) {
                int yy = y - 16;            // V_START lines of back porch before the picture
                if (yy >= 0 && yy < H && x < W) fb[yy * W + x] = t->video_rgb;
                x++;
            }
        }
        t->clk_74a = 0;
        if (c % 12 == 6) t->clk_pix = 0;
        t->eval();
    }
    FILE *f = fopen("sim/work/frame.ppm", "wb");
    fprintf(f, "P6\n%d %d\n255\n", W, H);
    for (uint32_t p : last) { fputc(p >> 16, f); fputc(p >> 8 & 0xFF, f); fputc(p & 0xFF, f); }
    fclose(f);
    printf("%d frames, mouse counter %u\n", frames, mcnt);
    delete t;
    return 0;
}
