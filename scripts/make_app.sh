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

echo "==> Compiling Metal shaders for MLX…"
METAL_SOURCES_DIR="$ROOT/.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
METAL_KERNEL_DIR="$ROOT/.build/checkouts/mlx-swift/Source/Cmlx/mlx/mlx/backend/metal/kernels"
METAL_TMP="$BUILD_DIR/metal_tmp"
rm -rf "$METAL_TMP"
mkdir -p "$METAL_TMP"

# Collect all .metal source files from MLX
METAL_FILES=()
if [ -d "$METAL_SOURCES_DIR" ]; then
  while IFS= read -r f; do METAL_FILES+=("$f"); done < <(find "$METAL_SOURCES_DIR" -name "*.metal" -type f)
fi
if [ -d "$METAL_KERNEL_DIR" ]; then
  while IFS= read -r f; do METAL_FILES+=("$f"); done < <(find "$METAL_KERNEL_DIR" -name "*.metal" -type f)
fi

if [ ${#METAL_FILES[@]} -gt 0 ]; then
  # Build include paths for Metal headers
  METAL_INCLUDE_PATHS=(
    "-I" "$ROOT/.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal"
    "-I" "$ROOT/.build/checkouts/mlx-swift/Source/Cmlx/mlx/mlx/backend/metal/kernels"
    "-I" "$ROOT/.build/checkouts/mlx-swift/Source/Cmlx/mlx/mlx/backend/metal/kernels/steel"
    "-I" "$ROOT/.build/checkouts/mlx-swift/Source/Cmlx/mlx/mlx/backend/metal/kernels/steel/attn"
    "-I" "$ROOT/.build/checkouts/mlx-swift/Source/Cmlx/mlx/mlx/backend/metal/kernels/steel/conv"
    "-I" "$ROOT/.build/checkouts/mlx-swift/Source/Cmlx/mlx/mlx/backend/metal/kernels/steel/gemm"
  )

  AIR_FILES=()
  for metal_file in "${METAL_FILES[@]}"; do
    base="$(basename "$metal_file" .metal)"
    air_file="$METAL_TMP/${base}.air"
    if xcrun metal -c "$metal_file" -o "$air_file" \
        "${METAL_INCLUDE_PATHS[@]}" \
        -std=metal3.0 -target air64-apple-macos14.0 2>/dev/null; then
      AIR_FILES+=("$air_file")
    fi
  done

  if [ ${#AIR_FILES[@]} -gt 0 ]; then
    xcrun metallib "${AIR_FILES[@]}" -o "$METAL_TMP/default.metallib" 2>/dev/null && \
      echo "   Compiled ${#AIR_FILES[@]} Metal shaders into default.metallib" || \
      echo "   warning: metallib linking failed; MLX may fall back to JIT compilation."
  else
    echo "   warning: no Metal shaders compiled successfully."
  fi
else
  echo "   warning: no Metal source files found."
fi

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

# Copy compiled Metal library into the app bundle next to the executable.
if [ -f "$METAL_TMP/default.metallib" ]; then
  cp "$METAL_TMP/default.metallib" "$MACOS_DIR/default.metallib"
  echo "   Copied default.metallib into app bundle."
fi

# Also copy any pre-built .metallib files from the build directory.
find "$BIN_PATH" -name "*.metallib" -exec cp {} "$MACOS_DIR/" \;

# Copy dependency .bundle directories that may contain runtime resources.
for bundle in "$BIN_PATH"/*.bundle; do
  [ -d "$bundle" ] || continue
  name="$(basename "$bundle")"
  [ "$name" = "${APP_NAME}_${APP_NAME}.bundle" ] && continue
  cp -R "$bundle" "$RES_DIR/"
done

rm -rf "$METAL_TMP"

# Ad-hoc code signature so macOS will let it request Accessibility/Input
# Monitoring. Replace "-" with your Developer ID for distribution.
echo "==> Code signing (ad-hoc)…"
codesign --force --deep --sign - "$APP_DIR" || {
  echo "warning: codesign failed; the app may still run but permissions can be flaky." >&2
}

echo "==> Done: $APP_DIR"
echo "    Launch with:  open \"$APP_DIR\""
echo "    Then grant Accessibility + Input Monitoring in System Settings."
