#!/usr/bin/env bash
# Build every release asset locally, sign the appcast and copy the files that
# belong in the repository (release/) so a release can be audited offline.
#
# Usage: ./scripts/release_artifacts.sh [version] [--skip-build] [--commit]
#
# Environment:
#   SPARKLE_ACCOUNT          Keychain account holding the EdDSA key
#                            (default: ru.zheltukheen.wifa)
#   SPARKLE_PRIVATE_KEY_FILE Path to an exported EdDSA private key instead of
#                            the Keychain (wins over SPARKLE_ACCOUNT)
#   SIGN_UPDATE              Path to Sparkle's sign_update tool
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION=""
SKIP_BUILD=0
COMMIT=0

usage() {
    cat >&2 <<'EOF'
Usage: ./scripts/release_artifacts.sh [version] [--skip-build] [--commit]

  <version>      SemVer without the leading "v" (default: project.yml)
  --skip-build   Reuse build/LanFi-Universal/LanFi.app from ./build.sh
  --commit       Stage release/ and commit it with a release message
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-build) SKIP_BUILD=1 ;;
        --commit) COMMIT=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option $1" >&2; usage; exit 1 ;;
        *)
            if [ -n "$VERSION" ]; then
                echo "Unexpected argument $1" >&2
                usage
                exit 1
            fi
            VERSION="$1"
            ;;
    esac
    shift
done

if [ -z "$VERSION" ]; then
    VERSION="$(awk '/^[[:space:]]*MARKETING_VERSION:/ {gsub(/"/, "", $2); print $2; exit}' project.yml)"
fi
BUILD="$(awk '/^[[:space:]]*CURRENT_PROJECT_VERSION:/ {gsub(/"/, "", $2); print $2; exit}' project.yml)"
APP="build/LanFi-Universal/LanFi.app"
DIST="build/dist"
STABLE="$DIST/stable"
RELEASE_DIR="release"

test -n "$VERSION" || { echo "Could not read MARKETING_VERSION" >&2; exit 1; }
echo "==> LanFi ${VERSION} (${BUILD})"

if [ ! -d "LanFi.xcodeproj" ]; then
    xcodegen generate
fi

if [ "$SKIP_BUILD" = "1" ]; then
    test -d "$APP" || {
        echo "--skip-build was passed but $APP does not exist; run ./build.sh first" >&2
        exit 1
    }
else
    ./build.sh
fi

echo "==> Packaging app"
rm -rf "$DIST" "$RELEASE_DIR"
mkdir -p "$DIST" "$STABLE" "$RELEASE_DIR"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST/LanFi-${VERSION}.zip"

mkdir -p "$DIST/dmg"
cp -R "$APP" "$DIST/dmg/"
ln -s /Applications "$DIST/dmg/Applications"
hdiutil create \
    -volname "LanFi ${VERSION}" \
    -srcfolder "$DIST/dmg" \
    -ov -format UDZO \
    "$DIST/LanFi-${VERSION}.dmg" >/dev/null

echo "==> Building universal CLI"
xcodebuild build \
    -project LanFi.xcodeproj \
    -scheme lanfi-cli \
    -configuration Release \
    -derivedDataPath build/DerivedData \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    -quiet
CLI="$(find build/DerivedData/Build/Products/Release -maxdepth 1 -name lanfi-cli -type f | head -1)"
test -n "$CLI" || { echo "lanfi-cli was not built" >&2; exit 1; }
"$CLI" help >/dev/null
lipo -archs "$CLI"
mkdir -p "$DIST/cli"
cp "$CLI" "$DIST/cli/lanfi-cli"
(cd "$DIST" && zip -q "LanFi-CLI-${VERSION}.zip" cli/lanfi-cli)

echo "==> Stable names"
cp "$DIST/LanFi-${VERSION}.zip" "$STABLE/LanFi.zip"
cp "$DIST/LanFi-${VERSION}.dmg" "$STABLE/LanFi.dmg"
cp "$DIST/LanFi-CLI-${VERSION}.zip" "$STABLE/LanFi-CLI.zip"
(cd "$STABLE" && shasum -a 256 LanFi.dmg LanFi.zip LanFi-CLI.zip >LanFi.sha256)
printf '%s\n' "$VERSION" >"$STABLE/LanFi.version"

echo "==> Homebrew cask"
DMG_SHA="$(shasum -a 256 "$STABLE/LanFi.dmg" | awk '{print $1}')"
if [ -x scripts/update_cask.sh ] && [ -f Casks/lanfi.rb ]; then
    ./scripts/update_cask.sh "$VERSION" "$DMG_SHA"
fi

echo "==> Release notes"
python3 scripts/release_notes.py "$VERSION"

echo "==> Appcast"
SIGN_UPDATE="${SIGN_UPDATE:-}"
if [ -z "$SIGN_UPDATE" ]; then
    for candidate in "$HOME"/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update; do
        if [ -x "$candidate" ]; then
            SIGN_UPDATE="$candidate"
            break
        fi
    done
fi
if [ -z "$SIGN_UPDATE" ] || [ ! -x "$SIGN_UPDATE" ]; then
    echo "Sparkle sign_update not found; downloading Sparkle 2.10.1" >&2
    curl -sSL --max-time 180 \
        "https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz" \
        -o "$DIST/Sparkle.tar.xz"
    mkdir -p "$DIST/sparkle"
    tar -xf "$DIST/Sparkle.tar.xz" -C "$DIST/sparkle"
    SIGN_UPDATE="$DIST/sparkle/bin/sign_update"
fi

SIGN_ARGS=(-p)
if [ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]; then
    SIGN_ARGS+=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
else
    SIGN_ARGS+=(--account "${SPARKLE_ACCOUNT:-ru.zheltukheen.wifa}")
fi
SIGNATURE="$("$SIGN_UPDATE" "${SIGN_ARGS[@]}" "$STABLE/LanFi.zip")"
LENGTH="$(stat -f%z "$STABLE/LanFi.zip")"

python3 scripts/make_appcast.py \
    --version "$VERSION" \
    --build "$BUILD" \
    --url "https://github.com/zheltukheen/lanfi/releases/download/v${VERSION}/LanFi.zip" \
    --signature "$SIGNATURE" \
    --length "$LENGTH" \
    --notes release_notes.md \
    --output "$DIST/appcast.xml"
cp "$DIST/appcast.xml" "$STABLE/appcast.xml"

echo "==> Copying into $RELEASE_DIR/"
for name in appcast.xml LanFi.dmg LanFi.zip LanFi-CLI.zip LanFi.sha256 LanFi.version; do
    cp "$STABLE/$name" "$RELEASE_DIR/$name"
done
cp release_notes.md "$RELEASE_DIR/release-notes.md"

echo "==> Artifacts"
ls -lh "$RELEASE_DIR"
cat "$RELEASE_DIR/LanFi.version"

if [ "$COMMIT" = "1" ]; then
    git add "$RELEASE_DIR"
    if [ -f Casks/lanfi.rb ]; then
        git add Casks/lanfi.rb
    fi
    git commit -m "release: artifacts for ${VERSION}"
    echo "==> Committed $RELEASE_DIR and Casks/lanfi.rb"
fi
