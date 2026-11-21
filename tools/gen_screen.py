#!/usr/bin/env python3
"""Generate the input monitor's screen and font for the HDL.

Writes src/fpga/core/screen_rom.svh and src/fpga/core/font_rom.svh, both
included by src/fpga/core/im_top.sv.

The screen is 40 x 30 cells of 8 x 8 pixels (320 x 240). Each cell holds a
12-bit code:
  [11]    highlight (drawn in the label colour)
  [10:9]  kind: 0 = a character, 1 = a hex digit (field nibble [8:0]),
          2 = a bit flag, '1' or '.' (field bit [8:0]), 3 = the typed line
          (character [8:0] of it)
  [8:0]   the character, or the index

Fields in the layout are written {NAME:xN} (N hex digits of NAME, most
significant first; NAME must be 4N bits wide), {NAME:b} (one bit) or
{TYPED:t40}. The names are the snapshot signals of im_top.sv; FIELDS below
gives each one's width and expression.

Usage: python3 tools/gen_screen.py
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
CORE = os.path.join(HERE, '..', 'src', 'fpga', 'core')
COLS, ROWS = 40, 30

# name -> (width in bits, SystemVerilog expression over im_top's snapshot)
FIELDS = {}
for n in range(1, 5):
    FIELDS['T%d' % n] = (4, 's_key[%d][31:28]' % (n - 1))
    FIELDS['K%d' % n] = (32, 's_key[%d]' % (n - 1))
    FIELDS['J%d' % n] = (32, 's_joy[%d]' % (n - 1))
    FIELDS['G%d' % n] = (16, 's_trig[%d]' % (n - 1))
    FIELDS['R%d' % n] = (12, 's_rate[%d]' % (n - 1))
FIELDS.update({
    'MCNT': (16, 's_key[3][15:0]'),
    'MX': (16, "{s_joy[3][7:0], s_joy[3][15:8]}"),
    'MY': (16, "{s_trig[3][7:0], s_trig[3][15:8]}"),
    'MW': (8, 's_joy[3][31:24]'),
    'SW': (16, 's_sumw'),
    'LDX': (16, 's_ldx'),
    'LDY': (16, 's_ldy'),
    'SX': (16, 's_sumx'),
    'SY': (16, 's_sumy'),
    'REP': (16, 's_reports'),
    'SKIP': (16, 's_skips'),
    'PX': (12, "{3'd0, s_px}"),
    'PY': (12, "{4'd0, s_py}"),
    'KLO': (8, 's_key[2][7:0]'),
    'KHI': (8, 's_key[2][15:8]'),
    'LAST': (8, 's_last'),
    'PRESS': (16, 's_presses'),
})
for i in range(8):
    FIELDS['HJ%d' % i] = (32, 's_hj[%d]' % i)
    FIELDS['HT%d' % i] = (16, 's_ht[%d]' % i)
for b in range(5):
    FIELDS['B%d' % (16 + b)] = (1, 's_joy[3][%d]' % (16 + b))
for b in range(16):
    FIELDS['M%d' % b] = (1, 's_key[2][%d]' % b)
for i, (w, b) in enumerate((('joy', 0), ('joy', 8), ('joy', 16), ('joy', 24), ('trig', 0), ('trig', 8))):
    FIELDS['HC%d' % i] = (8, 's_%s[2][%d:%d]' % (w, b + 7, b))

# The layout: (row, text, highlight)
LAYOUT = [
    (0, 'INPUT MONITOR 0.1.3', True),
    (2, '   T KEY      JOY      TRIG RATE/S', True),
    (3, 'P1 {T1:x1} {K1:x8} {J1:x8} {G1:x4} {R1:x3}', False),
    (4, 'P2 {T2:x1} {K2:x8} {J2:x8} {G2:x4} {R2:x3}', False),
    (5, 'P3 {T3:x1} {K3:x8} {J3:x8} {G3:x4} {R3:x3}', False),
    (6, 'P4 {T4:x1} {K4:x8} {J4:x8} {G4:x4} {R4:x3}', False),
    (8, 'MOUSE: P4, TYPE 5 EXPECTED', True),
    (9, 'COUNTER {MCNT:x4} REPORTS {REP:x4} SKIPS {SKIP:x4}', False),
    (10, 'X  NOW {MX:x4}  LAST {LDX:x4}  SUM {SX:x4}', False),
    (11, 'Y  NOW {MY:x4}  LAST {LDY:x4}  SUM {SY:x4}', False),
    (12, 'BUTTONS J[20:16] {B20:b} {B19:b} {B18:b} {B17:b} {B16:b}', False),
    (13, 'WHEEL {MW:x2} SUM {SW:x4}  POINTER {PX:x3},{PY:x3}', False),
    (15, 'KEYBOARD: P3, TYPE 4 EXPECTED', True),
    (16, 'MODIFIERS     RIGHT    LEFT', False),
    (17, '              G A S C  G A S C', False),
    (18, ' KEY[7:0]  {KLO:x2}  {M7:b} {M6:b} {M5:b} {M4:b}  {M3:b} {M2:b} {M1:b} {M0:b}', False),
    (19, ' KEY[15:8] {KHI:x2}  {M15:b} {M14:b} {M13:b} {M12:b}  {M11:b} {M10:b} {M9:b} {M8:b}', False),
    (20, 'KEYS {HC0:x2} {HC1:x2} {HC2:x2} {HC3:x2} {HC4:x2} {HC5:x2}  LAST {LAST:x2}', False),
    (21, 'PRESSES {PRESS:x4}   TYPED:', False),
    (22, '{TYPED:t40}', False),
    (23, 'P4 LAST 8 REPORTS, NEWEST FIRST:', True),
    (24, ' {HJ0:x8} {HT0:x4}   {HJ1:x8} {HT1:x4}', False),
    (25, ' {HJ2:x8} {HT2:x4}   {HJ3:x8} {HT3:x4}', False),
    (26, ' {HJ4:x8} {HT4:x4}   {HJ5:x8} {HT5:x4}', False),
    (27, ' {HJ6:x8} {HT6:x4}   {HJ7:x8} {HT7:x4}', False),
    (29, 'P1 SELECT OR THE MENU CLEARS THE SUMS.', True),
]

# 5 x 7 glyphs in an 8 x 8 cell (columns 1-5, rows 0-6); '#' = ink
GLYPHS = {
    ' ': [''] * 7,
    '0': [' ### ', '#   #', '#  ##', '# # #', '##  #', '#   #', ' ### '],
    '1': ['  #  ', ' ##  ', '  #  ', '  #  ', '  #  ', '  #  ', ' ### '],
    '2': [' ### ', '#   #', '    #', '   # ', '  #  ', ' #   ', '#####'],
    '3': ['#####', '   # ', '  #  ', '   # ', '    #', '#   #', ' ### '],
    '4': ['   # ', '  ## ', ' # # ', '#  # ', '#####', '   # ', '   # '],
    '5': ['#####', '#    ', '#### ', '    #', '    #', '#   #', ' ### '],
    '6': ['  ## ', ' #   ', '#    ', '#### ', '#   #', '#   #', ' ### '],
    '7': ['#####', '    #', '   # ', '  #  ', ' #   ', ' #   ', ' #   '],
    '8': [' ### ', '#   #', '#   #', ' ### ', '#   #', '#   #', ' ### '],
    '9': [' ### ', '#   #', '#   #', ' ####', '    #', '   # ', ' ##  '],
    'A': [' ### ', '#   #', '#   #', '#####', '#   #', '#   #', '#   #'],
    'B': ['#### ', '#   #', '#   #', '#### ', '#   #', '#   #', '#### '],
    'C': [' ### ', '#   #', '#    ', '#    ', '#    ', '#   #', ' ### '],
    'D': ['###  ', '#  # ', '#   #', '#   #', '#   #', '#  # ', '###  '],
    'E': ['#####', '#    ', '#    ', '#### ', '#    ', '#    ', '#####'],
    'F': ['#####', '#    ', '#    ', '#### ', '#    ', '#    ', '#    '],
    'G': [' ### ', '#   #', '#    ', '# ###', '#   #', '#   #', ' ####'],
    'H': ['#   #', '#   #', '#   #', '#####', '#   #', '#   #', '#   #'],
    'I': [' ### ', '  #  ', '  #  ', '  #  ', '  #  ', '  #  ', ' ### '],
    'J': ['  ###', '   # ', '   # ', '   # ', '   # ', '#  # ', ' ##  '],
    'K': ['#   #', '#  # ', '# #  ', '##   ', '# #  ', '#  # ', '#   #'],
    'L': ['#    ', '#    ', '#    ', '#    ', '#    ', '#    ', '#####'],
    'M': ['#   #', '## ##', '# # #', '# # #', '#   #', '#   #', '#   #'],
    'N': ['#   #', '#   #', '##  #', '# # #', '#  ##', '#   #', '#   #'],
    'O': [' ### ', '#   #', '#   #', '#   #', '#   #', '#   #', ' ### '],
    'P': ['#### ', '#   #', '#   #', '#### ', '#    ', '#    ', '#    '],
    'Q': [' ### ', '#   #', '#   #', '#   #', '# # #', '#  # ', ' ## #'],
    'R': ['#### ', '#   #', '#   #', '#### ', '# #  ', '#  # ', '#   #'],
    'S': [' ####', '#    ', '#    ', ' ### ', '    #', '    #', '#### '],
    'T': ['#####', '  #  ', '  #  ', '  #  ', '  #  ', '  #  ', '  #  '],
    'U': ['#   #', '#   #', '#   #', '#   #', '#   #', '#   #', ' ### '],
    'V': ['#   #', '#   #', '#   #', '#   #', '#   #', ' # # ', '  #  '],
    'W': ['#   #', '#   #', '#   #', '# # #', '# # #', '# # #', ' # # '],
    'X': ['#   #', '#   #', ' # # ', '  #  ', ' # # ', '#   #', '#   #'],
    'Y': ['#   #', '#   #', ' # # ', '  #  ', '  #  ', '  #  ', '  #  '],
    'Z': ['#####', '    #', '   # ', '  #  ', ' #   ', '#    ', '#####'],
    ':': ['     ', '  #  ', '  #  ', '     ', '  #  ', '  #  ', '     '],
    '.': ['     ', '     ', '     ', '     ', '     ', ' ##  ', ' ##  '],
    ',': ['     ', '     ', '     ', '     ', ' ##  ', '  #  ', ' #   '],
    '-': ['     ', '     ', '     ', '#####', '     ', '     ', '     '],
    '+': ['     ', '  #  ', '  #  ', '#####', '  #  ', '  #  ', '     '],
    '=': ['     ', '     ', '#####', '     ', '#####', '     ', '     '],
    '/': ['     ', '    #', '   # ', '  #  ', ' #   ', '#    ', '     '],
    ';': ['     ', ' ##  ', ' ##  ', '     ', ' ##  ', '  #  ', ' #   '],
    '[': [' ### ', ' #   ', ' #   ', ' #   ', ' #   ', ' #   ', ' ### '],
    ']': [' ### ', '   # ', '   # ', '   # ', '   # ', '   # ', ' ### '],
    '(': ['   # ', '  #  ', ' #   ', ' #   ', ' #   ', '  #  ', '   # '],
    ')': [' #   ', '  #  ', '   # ', '   # ', '   # ', '  #  ', ' #   '],
    "'": ['  #  ', '  #  ', ' #   ', '     ', '     ', '     ', '     '],
    '?': [' ### ', '#   #', '    #', '   # ', '  #  ', '     ', '  #  '],
    '#': [' # # ', ' # # ', '#####', ' # # ', '#####', ' # # ', ' # # '],
    '_': ['     ', '     ', '     ', '     ', '     ', '     ', '#####'],
}


def parse_row(text):
    """[(kind, value)] cells for one row."""
    cells = []
    pos = 0
    for m in re.finditer(r'\{(\w+):([xbt])(\d*)\}', text):
        cells += [(0, ord(c)) for c in text[pos:m.start()]]
        name, kind, n = m.group(1), m.group(2), int(m.group(3) or 1)
        if kind == 't':
            cells += [(3, i) for i in range(n)]
        else:
            w, _ = FIELDS[name]
            if kind == 'x':
                assert w == 4 * n, (name, w, n)
                cells += [(1, ('nib', name, d)) for d in range(n)]
            else:
                assert w == 1, name
                cells.append((2, ('bit', name)))
        pos = m.end()
    cells += [(0, ord(c)) for c in text[pos:]]
    assert len(cells) <= COLS, (text, len(cells))
    return cells


def main():
    nibs, bits = [], []           # (expression, index)
    rom = {}
    for row, text, hi in LAYOUT:
        for col, (kind, v) in enumerate(parse_row(text)):
            if kind == 1:
                _, name, d = v
                w, expr = FIELDS[name]
                lo = w - 4 * (d + 1)
                nibs.append('%s[%d:%d]' % ('(' + expr + ')' if not expr.startswith('s_') or '[' in expr else expr, lo + 3, lo)
                            if w > 4 else expr)
                v = len(nibs) - 1
            elif kind == 2:
                _, name = v
                bits.append(FIELDS[name][1])
                v = len(bits) - 1
            elif kind == 0:
                assert chr(v) in GLYPHS, (text, chr(v))
            assert v < 512
            rom[(row, col)] = (int(hi) << 11) | (kind << 9) | v

    # Field expressions on a bit range of a bit range are not legal SV: give
    # each field a flat wire first.
    out = ['// Generated by tools/gen_screen.py: do not edit.', '']
    flat = {}
    for name, (w, expr) in FIELDS.items():
        if w > 1:
            out.append('wire [%d:0] f_%s = %s;' % (w - 1, name, expr))
            flat[expr] = 'f_' + name
    out.append('')
    out.append('localparam int NNIB = %d;' % len(nibs))
    out.append('localparam int NBIT = %d;' % len(bits))
    out.append('wire [3:0] nib [0:NNIB-1];')
    out.append('wire       bitf [0:NBIT-1];')
    # rebuild nibble expressions from the flat wires
    k = 0
    for row, text, hi in LAYOUT:
        for kind, v in parse_row(text):
            if kind == 1:
                _, name, d = v
                w, _ = FIELDS[name]
                lo = w - 4 * (d + 1)
                out.append('assign nib[%d] = f_%s[%d:%d];' % (k, name, lo + 3, lo))
                k += 1
    for i, e in enumerate(bits):
        out.append('assign bitf[%d] = %s;' % (i, e))
    out.append('')
    out.append('function automatic logic [11:0] screen_code(input logic [4:0] row, input logic [5:0] col);')
    out.append('    case ({row, col})')
    for (row, col), code in sorted(rom.items()):
        if code != ord(' '):
            out.append("        {5'd%d, 6'd%d}: screen_code = 12'h%03X;" % (row, col, code))
    out.append("        default: screen_code = 12'h020;")
    out.append('    endcase')
    out.append('endfunction')
    open(os.path.join(CORE, 'screen_rom.svh'), 'w').write('\n'.join(out) + '\n')

    f = ['// Generated by tools/gen_screen.py: do not edit.', '// 5 x 7 glyphs, codes 0x20-0x5F; bit 7 = the left pixel.', '',
         'function automatic logic [7:0] font_row(input logic [6:0] ch, input logic [2:0] r);',
         '    case ({ch, r})']
    for ch, rows in sorted(GLYPHS.items()):
        for r, line in enumerate(rows):
            line = line.ljust(5)
            byte = 0
            for c, p in enumerate(line):
                if p == '#':
                    byte |= 0x80 >> (c + 1)
            if byte:
                f.append("        {7'h%02X, 3'd%d}: font_row = 8'h%02X;" % (ord(ch), r, byte))
    f += ["        default: font_row = 8'h00;", '    endcase', 'endfunction']
    open(os.path.join(CORE, 'font_rom.svh'), 'w').write('\n'.join(f) + '\n')
    print('screen: %d cells, %d nibbles, %d bits; font: %d glyphs' % (len(rom), len(nibs), len(bits), len(GLYPHS)))


if __name__ == '__main__':
    main()
