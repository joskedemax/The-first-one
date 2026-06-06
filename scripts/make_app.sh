#!/usr/bin/env bash
#
# Build JosType in release mode and assemble a runnable JosType.app bundle.
# Run from the repo root:  ./scripts/make_app.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="JosType"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

echo "==> Building (release)…"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)"

echo "==> Assembling $APP_NAME.app…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

cp "$BIN_PATH/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

# SwiftPM emits resources in a bundle named JosType_JosType.bundle; copy it in so
# Bundle.module resolves at runtime inside the .app.
if [ -d "$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle" ]; then
  cp -R "$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle" "$RES_DIR/"
fi

# Copy Metal shader libraries (.metallib) required by MLX into the app bundle
# so the GPU backend can find them at runtime.
find "$BIN_PATH" -name "*.metallib" -exec cp {} "$MACOS_DIR/" \;

# Also copy any .bundle directories from dependencies (MLX, etc.) that contain
# Metal resources or other runtime assets.
for bundle in "$BIN_PATH"/*.bundle; do
  [ -d "$bundle" ] || continue
  name="$(basename "$bundle")"
  [ "$name" = "${APP_NAME}_${APP_NAME}.bundle" ] && continue
  cp -R "$bundle" "$RES_DIR/"
done

# Ad-hoc code signature so macOS will let it request Accessibility/Input
# Monitoring. Replace "-" with your Developer ID for distribution.
echo "==> Code signing (ad-hoc)…"
codesign --force --deep --sign - "$APP_DIR" || {
  echo "warning: codesign failed; the app may still run but permissions can be flaky." >&2
}

echo "==> Done: $APP_DIR"
echo "    Launch with:  open \"$APP_DIR\""
echo "    Then grant Accessibility + Input Monitoring in System Settings."
