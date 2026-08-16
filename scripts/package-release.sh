#!/bin/bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
VERSION=${1:-0.0.3-beta-rr2}
BUILD_ROOT=$(mktemp -d /tmp/surrealra1n-package.XXXXXX)
DERIVED_DATA="$BUILD_ROOT/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Release/surrealra1n.app"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/surrealra1n"
STAGING_DIR="$BUILD_ROOT/dmg"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/surrealra1n-$VERSION-macOS-universal.dmg"
PKG_PATH="$DIST_DIR/surrealra1n-$VERSION-macOS-universal.pkg"

cleanup() {
    rm -rf "$BUILD_ROOT"
}

trap cleanup EXIT

mkdir -p "$DIST_DIR" "$STAGING_DIR"

xcodebuild \
    -project "$ROOT_DIR/Surrealra1nGUI.xcodeproj" \
    -scheme Surrealra1nGUI \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    build

if ! lipo "$APP_EXECUTABLE" -verify_arch arm64 x86_64; then
    echo "error: release binary is not universal (arm64 and x86_64)" >&2
    exit 1
fi

lipo -info "$APP_EXECUTABLE"

codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"

ditto "$APP_PATH" "$STAGING_DIR/surrealra1n.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH" "$PKG_PATH"

hdiutil create \
    -volname "surrealra1n $VERSION" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -ov \
    "$DMG_PATH"

pkgbuild \
    --component "$APP_PATH" \
    --install-location /Applications \
    --identifier com.surrealra1n.gui \
    --version "${VERSION%%-*}" \
    "$PKG_PATH"

hdiutil verify "$DMG_PATH"
pkgutil --check-signature "$PKG_PATH" || true

shasum -a 256 "$DMG_PATH" "$PKG_PATH"
