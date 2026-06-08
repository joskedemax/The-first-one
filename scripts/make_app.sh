#!/usr/bin/env bash
#
# Build JosType and assemble a runnable JosType.app bundle.
# Run from the repo root:  ./scripts/make_app.sh
#
# IMPORTANT: We build with `xcodebuild`, NOT `swift build`. MLX (mlx-swift)
# ships Metal compute shaders that must be compiled into a `default.metallib`
# via its `PrepareMetalShaders` plugin. SwiftPM's command-line build cannot
# compile Metal shaders — only Xcode's build system (xcodebuild) can. Using
# `swift build` produces a binary that crashes at runtime with:
#   "Failed to load the default metallib. library not found"
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
DERIVED="$BUILD_DIR/DerivedData"

echo "==> Building (release) via xcodebuild…"
echo "    (This compiles MLX's Metal shaders — first build is slow.)"
xcodebuild build \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  | (xcpretty 2>/dev/null || cat)

PRODUCTS="$DERIVED/Build/Products/Release"

if [ ! -f "$PRODUCTS/$APP_NAME" ]; then
  echo "error: built executable not found at $PRODUCTS/$APP_NAME" >&2
  echo "       Listing products dir:" >&2
  ls -la "$PRODUCTS" >&2 || true
  exit 1
fi

echo "==> Assembling $APP_NAME.app…"
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

cp "$PRODUCTS/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

# Copy every resource bundle xcodebuild produced (app's own resources plus
# dependency bundles such as mlx-swift_Cmlx.bundle, which holds the metallib).
shopt -s nullglob
for bundle in "$PRODUCTS"/*.bundle; do
  cp -R "$bundle" "$RES_DIR/"
done

# The MLX Metal device looks for its metallib relative to the executable and
# relative to the bundle. Make sure mlx-swift_Cmlx.bundle is also reachable
# next to the binary, and surface default.metallib directly beside it too.
MLX_BUNDLE="$PRODUCTS/mlx-swift_Cmlx.bundle"
if [ -d "$MLX_BUNDLE" ]; then
  cp -R "$MLX_BUNDLE" "$MACOS_DIR/"
  METALLIB="$(find "$MLX_BUNDLE" -name "*.metallib" -print -quit || true)"
  if [ -n "${METALLIB:-}" ]; then
    cp "$METALLIB" "$MACOS_DIR/default.metallib"
    echo "   Bundled $(basename "$METALLIB") -> default.metallib"
  fi
else
  echo "   warning: mlx-swift_Cmlx.bundle not found in build products." >&2
  echo "            MLX inference will fail to load its Metal shaders." >&2
fi
shopt -u nullglob

# Ad-hoc code signature so macOS will let it request Accessibility/Input
# Monitoring. Replace "-" with your Developer ID for distribution.
echo "==> Code signing (ad-hoc)…"
codesign --force --deep --sign - "$APP_DIR" || {
  echo "warning: codesign failed; the app may still run but permissions can be flaky." >&2
}

echo "==> Done: $APP_DIR"
echo "    Launch with:  open \"$APP_DIR\""
echo "    Then grant Accessibility + Input Monitoring in System Settings."
