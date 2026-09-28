#!/bin/bash
# Build astrid-core for every Apple slice the apps ship, package it as an XCFramework, and
# regenerate the Swift bindings.
#
#   scripts/core/build-xcframework.sh                     # against the revision core/Cargo.toml pins
#   scripts/core/build-xcframework.sh --core ../astrid-core  # against a local checkout
#   scripts/core/build-xcframework.sh --zip               # also zip it and print the SwiftPM checksum
#
# Output:
#   Packages/AstridCore/AstridCoreFFI.xcframework           (gitignored; what a local build links)
#   Packages/AstridCore/Sources/AstridCoreBindings/astrid_apple.swift   (committed)
#   build/core/AstridCoreFFI.xcframework.zip + its checksum (with --zip; what a release uploads)
#
# Why a prebuilt framework rather than building Rust inside Xcode: Xcode Cloud has no Rust
# toolchain, and installing one on every run would spend the compute allotment that ran out on
# 2026-08-18. The apps pin a released zip by URL and checksum instead (Packages/AstridCore/
# Package.swift), exactly as they would pin any binary dependency.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CORE_DIR="$ROOT/core"
PACKAGE_DIR="$ROOT/Packages/AstridCore"
OUT_DIR="$ROOT/build/core"
export PATH="$HOME/.cargo/bin:$PATH"

LOCAL_CORE=""
ZIP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --core) LOCAL_CORE="$(cd "$2" && pwd)"; shift 2 ;;
    --zip) ZIP=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

CARGO_ARGS=(--release -p astrid-apple --manifest-path "$CORE_DIR/Cargo.toml")
if [ -n "$LOCAL_CORE" ]; then
  CARGO_ARGS+=(--config "patch.\"https://github.com/Graceful-Tools/astrid-core.git\".astrid-core.path=\"$LOCAL_CORE/crates/astrid-core\"")
  echo "── building against the local core at $LOCAL_CORE ($(git -C "$LOCAL_CORE" rev-parse --short HEAD))"
fi

# The deployment targets the apps declare. Rust links against these SDK versions; a newer one would
# warn on every link and could call an API the oldest supported OS lacks.
export IPHONEOS_DEPLOYMENT_TARGET=18.0
export MACOSX_DEPLOYMENT_TARGET=14.0

TARGETS=(aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios aarch64-apple-darwin x86_64-apple-darwin)
for target in "${TARGETS[@]}"; do
  rustup target add "$target" >/dev/null 2>&1 || true
  start=$(date +%s)
  cargo build "${CARGO_ARGS[@]}" --target "$target"
  echo "── $target built in $(( $(date +%s) - start ))s"
done

LIB=libastrid_apple.a
TARGET_DIR="$CORE_DIR/target"
rm -rf "$OUT_DIR" && mkdir -p "$OUT_DIR"/{ios,ios-sim,macos,headers/astrid_appleFFI,swift}

# One slice per platform; the simulator and the Mac each carry both architectures.
cp "$TARGET_DIR/aarch64-apple-ios/release/$LIB" "$OUT_DIR/ios/$LIB"
lipo -create "$TARGET_DIR/aarch64-apple-ios-sim/release/$LIB" "$TARGET_DIR/x86_64-apple-ios/release/$LIB" \
  -output "$OUT_DIR/ios-sim/$LIB"
lipo -create "$TARGET_DIR/aarch64-apple-darwin/release/$LIB" "$TARGET_DIR/x86_64-apple-darwin/release/$LIB" \
  -output "$OUT_DIR/macos/$LIB"

# The bindings, read from the library's own metadata so they cannot describe a different build.
(cd "$CORE_DIR" && cargo run --quiet -p uniffi-bindgen -- generate \
  --library "$TARGET_DIR/aarch64-apple-darwin/release/$LIB" \
  --language swift --out-dir "$OUT_DIR/swift")

# Headers in a directory of their own: two XCFrameworks that both put `module.modulemap` at the top
# of Headers collide in Xcode's build products.
cp "$OUT_DIR/swift/astrid_appleFFI.h" "$OUT_DIR/headers/astrid_appleFFI/"
cp "$OUT_DIR/swift/astrid_appleFFI.modulemap" "$OUT_DIR/headers/astrid_appleFFI/module.modulemap"

rm -rf "$PACKAGE_DIR/AstridCoreFFI.xcframework"
xcodebuild -create-xcframework \
  -library "$OUT_DIR/ios/$LIB" -headers "$OUT_DIR/headers" \
  -library "$OUT_DIR/ios-sim/$LIB" -headers "$OUT_DIR/headers" \
  -library "$OUT_DIR/macos/$LIB" -headers "$OUT_DIR/headers" \
  -output "$PACKAGE_DIR/AstridCoreFFI.xcframework" >/dev/null

# Which core this is, for scripts/core/check-framework.sh: the pinned revision, or — built from a
# local checkout — that checkout's commit marked `+local`, which never matches a pin.
if [ -n "$LOCAL_CORE" ]; then
  STAMP="$(git -C "$LOCAL_CORE" rev-parse HEAD)+local"
else
  STAMP="$(sed -nE 's/^astrid-core = \{ git = "[^"]+", rev = "([0-9a-f]+)" \}/\1/p' "$CORE_DIR/Cargo.toml")"
fi
echo "$STAMP" > "$PACKAGE_DIR/AstridCoreFFI.xcframework/astrid-core-revision"

mkdir -p "$PACKAGE_DIR/Sources/AstridCoreBindings"
cp "$OUT_DIR/swift/astrid_apple.swift" "$PACKAGE_DIR/Sources/AstridCoreBindings/astrid_apple.swift"

echo "── sizes"
for slice in ios ios-sim macos; do du -h "$OUT_DIR/$slice/$LIB" | sed "s|$OUT_DIR/||"; done

if [ "$ZIP" -eq 1 ]; then
  (cd "$PACKAGE_DIR" && rm -f "$OUT_DIR/AstridCoreFFI.xcframework.zip" \
    && zip -qry "$OUT_DIR/AstridCoreFFI.xcframework.zip" AstridCoreFFI.xcframework)
  du -h "$OUT_DIR/AstridCoreFFI.xcframework.zip"
  echo "checksum: $(swift package compute-checksum "$OUT_DIR/AstridCoreFFI.xcframework.zip")"
fi
echo "RESULT: OK — Packages/AstridCore/AstridCoreFFI.xcframework"
