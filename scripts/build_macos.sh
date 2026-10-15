#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/macos"

mkdir -p "$DIST_DIR"

pushd "$ROOT_DIR" >/dev/null
swift build --disable-sandbox -c release --product SlopSandboxSDL >/dev/null
BIN_DIR="$(swift build --disable-sandbox -c release --show-bin-path)"
BIN_PATH="$BIN_DIR/SlopSandboxSDL"

if [[ ! -f "$BIN_PATH" ]]; then
  echo "error: SDL binary not found at $BIN_PATH" >&2
  exit 1
fi

cp "$BIN_PATH" "$DIST_DIR/SlopSandboxSDL"

if [[ -d "$ROOT_DIR/assets" ]]; then
  rm -rf "$DIST_DIR/assets"
  cp -R "$ROOT_DIR/assets" "$DIST_DIR/assets"
else
  mkdir -p "$DIST_DIR/assets"
fi

if [[ -f "$ROOT_DIR/config.json" ]]; then
  cp "$ROOT_DIR/config.json" "$DIST_DIR/config.json"
else
  printf '{}\n' > "$DIST_DIR/config.json"
fi

popd >/dev/null

echo "Built macOS dist at: dist/macos"
