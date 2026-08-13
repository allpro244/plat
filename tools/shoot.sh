#!/usr/bin/env bash
# Headless render. This is how every visual claim in this repository gets its
# evidence (CLAUDE.md rule 1). Runs the REAL Forward+/Vulkan renderer through
# lavapipe (software Vulkan) under Xvfb — no GPU, no editor, no human.
#
#   tools/shoot.sh [--out renders/shot.png] [--seed N] [--time H.H]
#                  [--date YYYY-MM-DD] [--band near|mid|far]
#                  [--az DEG] [--height M] [--radius M] [--res WxH]
#
# tools/shoot.sh --check   renders the same parameters twice and fails unless
# the two images are byte-identical (the determinism gate).
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT=${GODOT:-godot}
RES=1600x900
CHECK=0
ARGS=()
OUT=renders/shot.png
for a in "$@"; do
  case $a in
    --check) CHECK=1 ;;
    --res=*) RES=${a#--res=} ;;
    --out=*) OUT=${a#--out=}; ARGS+=("$a") ;;
    *) ARGS+=("$a") ;;
  esac
done

# lavapipe: pin the software Vulkan ICD so the render is the same everywhere.
export VK_ICD_FILENAMES=${VK_ICD_FILENAMES:-/usr/share/vulkan/icd.d/lvp_icd.json}

# One-time project import so the script-class registry and shader caches
# exist; cheap when already done.
if [ ! -d .godot ]; then
  "$GODOT" --path . --headless --import >/dev/null 2>&1 || true
fi

run() {
  xvfb-run -a "$GODOT" --path . \
    --rendering-driver vulkan --rendering-method forward_plus \
    --resolution "$RES" --fixed-fps 30 \
    -s src/shoot.gd -- "$@" 2>&1 | grep -v '^Godot Engine' || true
}

if [[ $CHECK -eq 1 ]]; then
  run "${ARGS[@]}" --out=renders/_det_a.png
  run "${ARGS[@]}" --out=renders/_det_b.png
  a=$(sha256sum renders/_det_a.png | cut -d' ' -f1)
  b=$(sha256sum renders/_det_b.png | cut -d' ' -f1)
  if [[ $a == "$b" ]]; then
    echo "DETERMINISM OK  $a"
  else
    echo "DETERMINISM FAILED: $a != $b"
    exit 1
  fi
else
  run "${ARGS[@]}"
fi
