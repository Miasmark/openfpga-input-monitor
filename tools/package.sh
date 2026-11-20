#!/bin/bash
# Assemble the SD card layout from a finished Quartus build:
#   dist/ + src/fpga/output_files/ap_core.rbf -> release/InputMonitor_Pocket_<version>.zip
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RBF="$ROOT/src/fpga/output_files/ap_core.rbf"
CORE="$ROOT/dist/Cores/Miasmark.InputMonitor"
VERSION=$(python3 -c "import json;print(json.load(open('$CORE/core.json'))['core']['metadata']['version'])")

[ -f "$RBF" ] || { echo "missing $RBF - build first"; exit 1; }
python3 "$ROOT/tools/reverse_bits.py" "$RBF" "$CORE/inputmonitor.rbf_r"

mkdir -p "$ROOT/release"
OUT="$ROOT/release/InputMonitor_Pocket_${VERSION}.zip"
rm -f "$OUT"
# License texts travel with the bitstream: ours, and Analogue's APF license
# (it lives only in the source headers; copied word for word).
LIC="$CORE/licenses"
mkdir -p "$LIC"
cp "$ROOT/LICENSE" "$LIC/"
awk '{ sub(/\r$/, "") } /^$/ { print; next } /^\/\/ *$/ || !/^\/\// { exit } { sub(/^\/\/ ?/, ""); print }' \
	"$ROOT/src/fpga/apf/apf_top.v" > "$LIC/Analogue-APF-Software-License.txt"
(cd "$ROOT/dist" && python3 - "$OUT" <<'PY'
import os, sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED) as z:
    for top in ("Cores", "Platforms"):
        for d, _, files in os.walk(top):
            z.write(d)
            for f in files:
                if f != ".keep":
                    z.write(os.path.join(d, f))
PY
)
echo "$OUT"
