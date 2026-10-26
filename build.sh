#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

APP_NAME="LanFi"
SCHEME="$APP_NAME"
PROJECT="$APP_NAME.xcodeproj"
OUT_DIR="build"
ARCHIVE_PATH="$OUT_DIR/${APP_NAME}.xcarchive"
PRODUCT_PATH="$OUT_DIR/${APP_NAME}-Universal"
CLEAN_ARCHIVE="${CLEAN_ARCHIVE:-1}"

if [ ! -d "$PROJECT" ]; then
    echo "Error: $PROJECT not found. Run 'xcodegen generate' first." >&2
    exit 1
fi

echo "==> Cleaning previous Release artifacts"
rm -rf "$ARCHIVE_PATH" "$PRODUCT_PATH"
mkdir -p "$OUT_DIR"

echo "==> Archiving universal macOS app (arm64 + x86_64)"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$OUT_DIR/DerivedData" \
    -configuration Release \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS="arm64 x86_64" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    SKIP_INSTALL=NO

mkdir -p "$PRODUCT_PATH"
cp -R "$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app" "$PRODUCT_PATH/"

APP="$PRODUCT_PATH/${APP_NAME}.app"
# Set CODESIGN_IDENTITY to a Developer ID Application identity for distribution
# outside GitHub; the default ad-hoc signature is fine for local builds.
IDENTITY="${CODESIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
    codesign --force --deep --sign - "$APP"
else
    codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

if [ "$CLEAN_ARCHIVE" = "1" ]; then
    rm -rf "$ARCHIVE_PATH"
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
echo "==> Built LanFi ${VERSION} (${BUILD})"
lipo -archs "$APP/Contents/MacOS/${APP_NAME}"
echo "==> App: $APP"
