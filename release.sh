#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-}"
BUILD="${BUILD:-}"
CHANGELOG="CHANGELOG.md"
PROJECT_SPEC="project.yml"
TAG="v${VERSION}"

if [ -z "$VERSION" ]; then
    echo "Usage: ./release.sh <version> [BUILD=number]" >&2
    exit 1
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: version must look like 1.2.3" >&2
    exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: not inside a git repository." >&2
    exit 1
fi

if [ ! -f "$CHANGELOG" ]; then
    echo "Error: $CHANGELOG not found." >&2
    exit 1
fi

if ! grep -Eq "^##[[:space:]]+${VERSION//./\\.}([[:space:]]|$|—|-)" "$CHANGELOG"; then
    echo "Error: CHANGELOG.md is missing a section for ${VERSION}." >&2
    echo "Add a section like: \"## ${VERSION} — YYYY-MM-DD\" before releasing." >&2
    exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Error: tag ${TAG} already exists." >&2
    exit 1
fi

if [ -z "$BUILD" ]; then
    CURRENT_BUILD="$(awk '/^[[:space:]]*CURRENT_PROJECT_VERSION:/ {gsub(/"/, "", $2); print $2; exit}' "$PROJECT_SPEC")"
    if [[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
        BUILD=$((CURRENT_BUILD + 1))
    else
        BUILD="$(date +%s)"
    fi
fi

python3 - "$VERSION" "$BUILD" <<'PY'
import re
import sys
from pathlib import Path

version, build = sys.argv[1], sys.argv[2]
path = Path("project.yml")
text = path.read_text(encoding="utf-8")
text, version_count = re.subn(
    r'(?m)^(\\s*MARKETING_VERSION:\\s*).*$', rf'\\g<1>"{version}"', text
)
text, build_count = re.subn(
    r'(?m)^(\\s*CURRENT_PROJECT_VERSION:\\s*).*$', rf'\\g<1>"{build}"', text
)
if version_count != 1 or build_count != 1:
    raise SystemExit("Could not update version fields in project.yml")
path.write_text(text, encoding="utf-8")
print(f"project.yml -> {version} ({build})")
PY

if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate
else
    echo "Error: xcodegen is required to regenerate the Xcode project." >&2
    exit 1
fi

git add -A
if git diff --cached --quiet; then
    echo "No changes to commit."
    exit 1
fi

git commit -m "release: ${VERSION}"
git push origin HEAD:main
git tag "$TAG"
git push origin "$TAG"

echo "Release ${TAG} pushed. GitHub Actions will build and publish the artifacts."
