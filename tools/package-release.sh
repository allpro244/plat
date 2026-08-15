#!/usr/bin/env bash
# Build double-click zips: plat + portable node + plat-econ. No Godot install
# needed on the player's machine.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-dev}"
NODE_VER="22.14.0"
DIST="dist/releases"
mkdir -p "$DIST"

echo "== assets =="
bash tools/fetch-assets.sh

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

echo "== plat-econ =="
if [ ! -d plat-econ/.git ]; then
  rm -rf plat-econ
  git clone --depth 1 https://github.com/allpro244/plat-econ.git plat-econ
fi
if [ ! -f plat-econ/test/.engine.mjs ]; then
  (
    cd plat-econ
    export CI=true
    corepack enable 2>/dev/null || true
    corepack prepare pnpm@10.33.3 --activate 2>/dev/null || true
    pnpm install --frozen-lockfile
    pnpm engine
  )
fi

write_play_txt() {
  cat > "$1/PLAY.txt" <<'EOF'
PLAT — Broadway & Wall in 3D

1. Double-click plat.exe (Windows) or plat.x86_64 (Linux).
2. Wait ~10 seconds while the city and your firm load.
3. Click any building to read its record and price.
4. Space = advance time.  B = buy selected.  H = full controls.

Left-drag pans.  Right-drag rotates.  Mouse wheel zooms.
EOF
}

pack_windows() {
  local dir="$DIST/plat-win64"
  rm -rf "$dir"
  mkdir -p "$dir"
  cp dist/plat-windows/plat.exe "$dir/"
  write_play_txt "$dir"
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/node.zip" \
    "https://nodejs.org/dist/v${NODE_VER}/node-v${NODE_VER}-win-x64.zip"
  unzip -qo "$tmp/node.zip" -d "$tmp"
  cp "$tmp/node-v${NODE_VER}-win-x64/node.exe" "$dir/"
  rm -rf "$tmp"
  rm -rf "$dir/plat-econ"
  mkdir -p "$dir/plat-econ"
  cp -a plat-econ/. "$dir/plat-econ/"
  rm -rf "$dir/plat-econ/.git"
  (cd "$DIST" && zip -qr "plat-win64-${VERSION}.zip" "plat-win64")
  echo "Wrote $DIST/plat-win64-${VERSION}.zip"
}

pack_linux() {
  local dir="$DIST/plat-linux64"
  rm -rf "$dir"
  mkdir -p "$dir"
  cp dist/plat-linux/plat.x86_64 "$dir/"
  write_play_txt "$dir"
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/node.tar.xz" \
    "https://nodejs.org/dist/v${NODE_VER}/node-v${NODE_VER}-linux-x64.tar.xz"
  tar -xJf "$tmp/node.tar.xz" -C "$tmp"
  cp "$tmp/node-v${NODE_VER}-linux-x64/bin/node" "$dir/"
  rm -rf "$tmp"
  rm -rf "$dir/plat-econ"
  mkdir -p "$dir/plat-econ"
  cp -a plat-econ/. "$dir/plat-econ/"
  rm -rf "$dir/plat-econ/.git"
  (cd "$DIST" && zip -qr "plat-linux64-${VERSION}.zip" "plat-linux64")
  echo "Wrote $DIST/plat-linux64-${VERSION}.zip"
}

echo "== pack =="
pack_windows
pack_linux
ls -lh "$DIST"/*.zip
