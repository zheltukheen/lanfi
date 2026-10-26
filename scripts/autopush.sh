#!/usr/bin/env bash
#
# autopush.sh — keep the LanFi GitHub repository in sync automatically.
#
# Modes:
#   ./scripts/autopush.sh                  commit meaningful local changes and push
#   ./scripts/autopush.sh --watch          wait for a quiet period, then commit + push
#   ./scripts/autopush.sh --push-only      push the current branch (used by the hook)
#   ./scripts/autopush.sh --install-hook   install a post-commit hook that auto-pushes
#   ./scripts/autopush.sh --uninstall-hook remove that hook
#   ./scripts/autopush.sh --status         show whether auto-push is configured
#
# Environment overrides:
#   AUTOPUSH_REMOTE=origin  AUTOPUSH_BRANCH=main
#   AUTOPUSH_QUIET=90       seconds of no file changes before --watch commits
#   AUTOPUSH_INTERVAL=5     seconds between --watch polls
#   AUTOPUSH_MESSAGE="..."  force a commit subject
#   AUTOPUSH_DRY_RUN=1      print what would happen without committing/pushing
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
REMOTE="${AUTOPUSH_REMOTE:-origin}"
BRANCH="${AUTOPUSH_BRANCH:-main}"
QUIET="${AUTOPUSH_QUIET:-90}"
INTERVAL="${AUTOPUSH_INTERVAL:-5}"
DRY_RUN="${AUTOPUSH_DRY_RUN:-0}"
HOOK_MARKER="# LanFi autopush hook"
HOOK_PATH=""

log() { printf '[autopush] %s\n' "$*"; }
die() { printf '[autopush] error: %s\n' "$*" >&2; exit 1; }

require_repo() {
  [ -n "$REPO_ROOT" ] || die "not inside a git repository"
  cd "$REPO_ROOT"
  HOOK_PATH="$(git rev-parse --git-path hooks/post-commit)"
  [ "${HOOK_PATH#/}" = "$HOOK_PATH" ] && HOOK_PATH="$REPO_ROOT/$HOOK_PATH"
}

ensure_branch() {
  local current
  current="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  [ -n "$current" ] || die "detached HEAD; refusing to auto-push"
  if [ "$current" != "$BRANCH" ]; then
    die "on branch '$current', expected '$BRANCH' (set AUTOPUSH_BRANCH to override)"
  fi
}

# Files that should never trigger an automatic commit. Build output and IDE
# state are already ignored by .gitignore; this guards against accidents.
is_meaningful_path() {
  case "$1" in
    build/*|DerivedData/*|.build/*|.swiftpm/*) return 1 ;;
    *.xcuserstate|*.xcscmblueprint|*.xccheckout|*.dSYM|*.log|*.zip) return 1 ;;
    */.DS_Store|.DS_Store) return 1 ;;
    .idea/*|.vscode/*) return 1 ;;
  esac
  return 0
}

has_meaningful_changes() {
  local path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if is_meaningful_path "$path"; then
      return 0
    fi
  done < <(git status --porcelain=v1 --untracked-files=all | sed -E 's/^...//; s/^.* -> //')
  return 1
}

# Refuse to publish obvious credentials or oversized binaries.
safety_checks() {
  local secret_pattern='(ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY-----|sk-[A-Za-z0-9]{24,})'
  if git diff --cached -U0 | grep -Eq "$secret_pattern"; then
    die "possible credential in staged changes; commit aborted"
  fi

  local big
  big="$(git diff --cached --name-only --diff-filter=ACM | while IFS= read -r f; do
    [ -f "$f" ] || continue
    if [ "$(wc -c <"$f" | tr -d ' ')" -gt 10485760 ]; then echo "$f"; fi
  done)"
  [ -z "$big" ] || die "refusing to commit files larger than 10 MB: $big"
}

commit_subject() {
  if [ -n "${AUTOPUSH_MESSAGE:-}" ]; then
    printf '%s' "$AUTOPUSH_MESSAGE"
    return
  fi

  local summary
  summary="$(git diff --cached --stat | tail -n 1 | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  printf 'chore: sync working tree (%s)' "${summary:-local changes}"
}

commit_changes() {
  git add -A
  if git diff --cached --quiet; then
    log "nothing to commit"
    return 1
  fi

  safety_checks
  local subject
  subject="$(commit_subject)"
  if [ "$DRY_RUN" = "1" ]; then
    log "dry run: would commit '$subject'"
    git reset --quiet
    return 1
  fi

  # Do not let the post-commit hook push in the middle of this script.
  WIFA_AUTOPUSH_ACTIVE=1 git commit --quiet -m "$subject"
  log "committed: $subject"
  return 0
}

push_changes() {
  local attempt
  for attempt in 1 2 3; do
    if [ "$DRY_RUN" = "1" ]; then
      log "dry run: would push HEAD to $REMOTE/$BRANCH"
      return 0
    fi
    if git push --quiet "$REMOTE" "HEAD:$BRANCH"; then
      log "pushed to $REMOTE/$BRANCH"
      return 0
    fi

    log "push failed (attempt $attempt/3); rebasing on $REMOTE/$BRANCH"
    if ! git pull --quiet --rebase --autostash "$REMOTE" "$BRANCH"; then
      git rebase --abort 2>/dev/null || true
      die "could not rebase on $REMOTE/$BRANCH; resolve manually"
    fi
    sleep 2
  done
  die "push failed after 3 attempts"
}

sync_once() {
  require_repo
  ensure_branch
  if has_meaningful_changes; then
    commit_changes || true
  fi
  if git rev-parse --verify --quiet "@{u}" >/dev/null 2>&1; then
    local ahead
    ahead="$(git rev-list --count '@{u}..HEAD')"
    if [ "$ahead" = "0" ] && ! has_meaningful_changes; then
      log "already up to date"
      return 0
    fi
  fi
  push_changes
}

watch_loop() {
  require_repo
  ensure_branch
  log "watching $REPO_ROOT (quiet=${QUIET}s, poll=${INTERVAL}s)"
  local snapshot last_change now
  snapshot="$(git status --porcelain=v1 --untracked-files=all)"
  last_change=0
  if has_meaningful_changes; then last_change="$(date +%s)"; fi

  while true; do
    sleep "$INTERVAL"
    now="$(date +%s)"
    local current
    current="$(git status --porcelain=v1 --untracked-files=all)"
    if [ "$current" != "$snapshot" ]; then
      snapshot="$current"
      last_change="$now"
      continue
    fi
    if has_meaningful_changes && [ "$last_change" -gt 0 ] && [ $((now - last_change)) -ge "$QUIET" ]; then
      if sync_once; then
        last_change=0
      fi
    fi
  done
}

install_hook() {
  require_repo
  mkdir -p "$(dirname "$HOOK_PATH")"
  cat >"$HOOK_PATH" <<EOF
#!/usr/bin/env bash
$HOOK_MARKER
# Automatically push completed commits. Set WIFA_AUTOPUSH_ACTIVE=1 to suppress.
[ "\${WIFA_AUTOPUSH_ACTIVE:-0}" = "1" ] && exit 0
[ "\${WIFA_AUTOPUSH_DISABLE:-0}" = "1" ] && exit 0
"$REPO_ROOT/scripts/autopush.sh" --push-only || true
EOF
  chmod +x "$HOOK_PATH"
  log "installed post-commit hook at ${HOOK_PATH#"$REPO_ROOT/"}"
}

uninstall_hook() {
  require_repo
  if [ -f "$HOOK_PATH" ] && grep -qF "$HOOK_MARKER" "$HOOK_PATH"; then
    rm -f "$HOOK_PATH"
    log "removed post-commit hook"
  else
    log "no autopush hook installed"
  fi
}

status() {
  require_repo
  echo "repository: $REPO_ROOT"
  echo "branch:     $(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo detached)"
  echo "remote:     $REMOTE/$BRANCH"
  echo "hook:       $([ -f "$HOOK_PATH" ] && grep -qF "$HOOK_MARKER" "$HOOK_PATH" && echo installed || echo absent)"
  echo "changes:    $(has_meaningful_changes && echo yes || echo no)"
  echo "ahead:      $(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo n/a)"
}

case "${1:-once}" in
  once) sync_once ;;
  --watch|watch) watch_loop ;;
  --push-only|push-only) require_repo; ensure_branch; push_changes ;;
  --install-hook|install-hook) install_hook ;;
  --uninstall-hook|uninstall-hook) uninstall_hook ;;
  --status|status) require_repo; status ;;
  -h|--help|help)
    awk 'NR==1{next} /^set -euo/{exit} {sub(/^# ?/,""); print}' "${BASH_SOURCE[0]}"
    ;;
  *) die "unknown option: $1 (try --help)" ;;
esac
