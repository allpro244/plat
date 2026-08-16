#!/usr/bin/env bash
# Build double-click zips: plat + plat-sim. No Godot or Node install on the
# player's machine. The economy is the SEA sidecar, not a plat-econ tree.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-dev}"
DIST="dist/releases"
mkdir -p "$DIST"

echo "== assets =="
bash tools/fetch-assets.sh

echo "== plat-sim sidecar =="
bash tools/build-plat-sim.sh linux,windows

echo "== godot export templates =="
TEMPLATE_DIR="$HOME/.local/share/godot/export_templates/4.5.stable"
if [ ! -f "$TEMPLATE_DIR/linux_release.x86_64" ]; then
  mkdir -p "$TEMPLATE_DIR"
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/templates.tpz" \
    "https://github.com/godotengine/godot/releases/download/4.5-stable/Godot_v4.5-stable_export_templates.tpz"
  unzip -qo "$tmp/templates.tpz" -d "$tmp/ex"
  mv "$tmp/ex/templates/"* "$TEMPLATE_DIR/"
  rm -rf "$tmp"
fi

if ! command -v godot >/dev/null; then
  bash tools/setup-linux.sh
fi

echo "== import + export =="
godot --headless --import >/dev/null 2>&1 || true
mkdir -p dist/plat-windows dist/plat-linux
godot --headless --export-release "Windows Desktop" dist/plat-windows/plat.exe
godot --headless --export-release "Linux" dist/plat-linux/plat.x86_64
chmod +x dist/plat-linux/plat.x86_64

write_play_txt() {
  cat > "$1/PLAY.txt" <<'EOF'
PLAT — Broadway & Wall in 3D

1. Double-click plat.exe (Windows) or plat.x86_64 (Linux).
   Keep plat-sim / plat-sim.exe in the same folder — that is the economy.
2. Wait ~10 seconds while the city and your firm load.
3. Break ground (or Continue). Click Acquire for the marketplace tape.
4. Click a listing or a building, then Buy at ask. Advance moves a month.

No Godot install. No Node install. Left-drag pans. Right-drag rotates.
Mouse wheel zooms.
EOF
}

pack_windows() {
  local dir="$DIST/plat-win64"
  rm -rf "$dir"
  mkdir -p "$dir"
  cp dist/plat-windows/plat.exe "$dir/"
  cp dist/plat-sim.exe "$dir/"
  write_play_txt "$dir"
  (cd "$DIST" && zip -qr "plat-win64-${VERSION}.zip" "plat-win64")
  echo "Wrote $DIST/plat-win64-${VERSION}.zip"
}

pack_linux() {
  local dir="$DIST/plat-linux64"
  rm -rf "$dir"
  mkdir -p "$dir"
  cp dist/plat-linux/plat.x86_64 "$dir/"
  cp dist/plat-sim "$dir/"
  chmod +x "$dir/plat-sim"
  write_play_txt "$dir"
  (cd "$DIST" && zip -qr "plat-linux64-${VERSION}.zip" "plat-linux64")
  echo "Wrote $DIST/plat-linux64-${VERSION}.zip"
}

echo "== pack =="
pack_windows
pack_linux
ls -lh "$DIST"/*.zip
