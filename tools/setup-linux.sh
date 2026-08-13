#!/usr/bin/env bash
# One-time machine setup for headless rendering on a GPU-less Linux box/CI:
# Godot 4.5 (pinned), lavapipe (Mesa software Vulkan) and Xvfb.
set -euo pipefail

GODOT_VERSION=4.5-stable
GODOT_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip"

if ! command -v godot >/dev/null; then
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/godot.zip" "$GODOT_URL"
  unzip -q "$tmp/godot.zip" -d "$tmp"
  sudo mv "$tmp/Godot_v${GODOT_VERSION}_linux.x86_64" /usr/local/bin/godot
  rm -rf "$tmp"
fi
godot --version

if [ ! -e /usr/share/vulkan/icd.d/lvp_icd.json ] && [ ! -e /usr/share/vulkan/icd.d/lvp_icd.x86_64.json ]; then
  sudo apt-get update -qq || true
  sudo apt-get install -y mesa-vulkan-drivers
fi
command -v xvfb-run >/dev/null || sudo apt-get install -y xvfb
echo "setup complete"
