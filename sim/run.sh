#!/bin/bash
# Simulate im_top with Verilator and write sim/work/frame.png (needs Python's PIL for the PNG).
# Usage: sim/run.sh [seconds]   (default 1.2: the rates need a whole second)
set -e
cd "$(dirname "$0")/.."
python3 tools/gen_screen.py
mkdir -p sim/work
verilator --cc --exe --build -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED --top-module im_top \
  -Isrc/fpga/core src/fpga/core/im_top.sv sim/tb.cpp -Mdir sim/work/obj -o tb >/dev/null
sim/work/obj/tb "$@"
python3 -c "from PIL import Image; Image.open('sim/work/frame.ppm').resize((960,720), Image.NEAREST).save('sim/work/frame.png')" && echo sim/work/frame.png
