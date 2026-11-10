#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="VoxKey"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
BUILD_ARTIFACT_DIR="$ROOT_DIR/builds/latest"
BUILD_ARTIFACT_ZIP="$BUILD_ARTIFACT_DIR/$APP_NAME.app.zip"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

if swift build -c release --arch arm64 --arch x86_64; then
    BINARY_PATH="$ROOT_DIR/.build/apple/Products/Release/$APP_NAME"
else
    echo "Universal build failed; falling back to host-architecture release build." >&2
    swift build -c release
    BINARY_PATH="$ROOT_DIR/.build/release/$APP_NAME"
fi

if [[ ! -f "$BINARY_PATH" ]]; then
    echo "Could not find built binary at $BINARY_PATH" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BINARY_PATH" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
if [[ -f "$ROOT_DIR/Packaging/VoxKey.icns" ]]; then
    cp "$ROOT_DIR/Packaging/VoxKey.icns" "$RESOURCES_DIR/VoxKey.icns"
fi
chmod +x "$MACOS_DIR/$APP_NAME"

# Embed the whisper.cpp framework (binary target) — the executable looks for it on the
# @executable_path/../lib rpath.
PRODUCTS_DIR="$(dirname "$BINARY_PATH")"
LIB_DIR="$CONTENTS_DIR/lib"
if [[ -d "$PRODUCTS_DIR/whisper.framework" ]]; then
    mkdir -p "$LIB_DIR"
    cp -R "$PRODUCTS_DIR/whisper.framework" "$LIB_DIR/"
fi

if [[ -d "$ROOT_DIR/.build/apple/Products/Release/VoxKey_VoxKey.bundle" ]]; then
    cp -R "$ROOT_DIR/.build/apple/Products/Release/VoxKey_VoxKey.bundle" "$RESOURCES_DIR/"
elif [[ -d "$ROOT_DIR/.build/release/VoxKey_VoxKey.resources" ]]; then
    cp -R "$ROOT_DIR/.build/release/VoxKey_VoxKey.resources/." "$RESOURCES_DIR/"
elif [[ -d "$ROOT_DIR/.build/release/VoxKey_VoxKey.bundle" ]]; then
    cp -R "$ROOT_DIR/.build/release/VoxKey_VoxKey.bundle" "$RESOURCES_DIR/"
fi

if command -v codesign >/dev/null 2>&1; then
    SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
    if [[ -z "$SIGN_IDENTITY" ]] && command -v security >/dev/null 2>&1; then
        SIGN_IDENTITY="$(
            security find-identity -v -p codesigning |
                sed -n 's/.*"\(Apple Development:.*\)".*/\1/p' |
                head -n 1
        )"
    fi
    SIGN_IDENTITY="${SIGN_IDENTITY:--}"
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null
fi

mkdir -p "$BUILD_ARTIFACT_DIR"
rm -f "$BUILD_ARTIFACT_ZIP"
(
    cd "$ROOT_DIR/dist"
    zip -qry -X "$BUILD_ARTIFACT_ZIP" "$APP_NAME.app"
)

echo "Packaged $APP_DIR"
echo "Wrote $BUILD_ARTIFACT_ZIP"
