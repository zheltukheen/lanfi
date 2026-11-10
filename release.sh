#!/usr/bin/env bash
# Tag a release: bump project.yml, verify (lint + tests), commit, tag and push.
# The pushed tag triggers .github/workflows/release.yml, which lints, tests,
# builds, publishes the unversioned artifacts and refreshes the always-latest
# aliases (LanFi.dmg / LanFi.zip in the newest release).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

REPO="zheltukheen/lanfi"
CHANGELOG="CHANGELOG.md"
PROJECT_SPEC="project.yml"

VERSION=""
BUILD="${BUILD:-}"
RUN_TESTS=1
ALLOW_DIRTY="${ALLOW_DIRTY:-0}"

usage() {
    cat >&2 <<'EOF'
Usage: ./release.sh <version> [--skip-tests]

  <version>      SemVer without the leading "v" (e.g. 4.12.0)
  --skip-tests   Do not run lint/XCTest locally (CI still runs them)

Environment:
  BUILD=number   Override CURRENT_PROJECT_VERSION (default: previous + 1)
  ALLOW_DIRTY=1  Allow releasing with a dirty working tree
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --skip-tests) RUN_TESTS=0 ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Error: unknown option $1" >&2; usage; exit 1 ;;
        *)
            if [ -n "$VERSION" ]; then
                echo "Error: unexpected argument $1" >&2
                usage
                exit 1
            fi
            VERSION="$1"
            ;;
    esac
    shift
done

TAG="v${VERSION}"

if [ -z "$VERSION" ]; then
    usage
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

if [ "$ALLOW_DIRTY" != "1" ] && [ -n "$(git status --porcelain)" ]; then
    echo "Error: working tree is dirty. Commit or stash your changes first" >&2
    echo "       (or pass ALLOW_DIRTY=1)." >&2
    git status --short >&2
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

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" != "main" ]; then
    echo "Warning: releasing from '${BRANCH}', not 'main'." >&2
fi

if [ "$RUN_TESTS" = "1" ]; then
    echo "==> Lint"
    ./scripts/lint.sh

    echo "==> Test"
    xcodebuild test \
        -project LanFi.xcodeproj \
        -scheme LanFi \
        -destination 'platform=macOS' \
        CODE_SIGNING_ALLOWED=NO
else
    echo "==> Skipping local lint/tests (--skip-tests)"
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
    r'(?m)^(\s*MARKETING_VERSION:\s*).*$', rf'\g<1>"{version}"', text
)
text, build_count = re.subn(
    r'(?m)^(\s*CURRENT_PROJECT_VERSION:\s*).*$', rf'\g<1>"{build}"', text
)
if version_count != 1 or build_count != 1:
    raise SystemExit("Could not update version fields in project.yml")
path.write_text(text, encoding="utf-8")
print(f"project.yml -> {version} ({build})")
PY

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "Error: xcodegen is required to regenerate the Xcode project." >&2
    exit 1
fi
xcodegen generate

git add -A
if git diff --cached --quiet; then
    echo "No changes to commit."
    exit 1
fi

git commit -m "release: ${VERSION}"
git push origin "HEAD:${BRANCH}"
git tag "$TAG"
git push origin "$TAG"

cat <<EOF

Release ${TAG} pushed. GitHub Actions will lint, test, build and publish.

  Always latest:  https://github.com/${REPO}/releases/latest/download/LanFi.dmg
  Short link:     https://zheltukheen.github.io/lanfi/download
  Pinned build:   https://github.com/${REPO}/releases/download/${TAG}/LanFi.dmg
  Release page:   https://github.com/${REPO}/releases/tag/${TAG}
EOF
