#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
SHA256="${2:-}"
CASK="Casks/wifa.rb"

if [ -z "$VERSION" ] || [ -z "$SHA256" ]; then
    echo "Usage: ./scripts/update_cask.sh <version> <dmg-sha256>" >&2
    exit 1
fi
if [ ! -f "$CASK" ]; then
    echo "Missing $CASK" >&2
    exit 1
fi

/usr/bin/sed -i '' -E "s/^  version \".*\"$/  version \"$VERSION\"/" "$CASK"
/usr/bin/sed -i '' -E "s/^  sha256 \".*\"$/  sha256 \"$SHA256\"/" "$CASK"
echo "Updated $CASK to $VERSION / $SHA256"
