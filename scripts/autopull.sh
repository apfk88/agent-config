#!/usr/bin/env bash
set -euo pipefail

timestamp() {
  date +"%Y-%m-%dT%H:%M:%S%z"
}

log() {
  printf '[%s] %s\n' "$(timestamp)" "$*"
}

repo_dir="${1:-}"
branch="${2:-}"

if [ -z "$repo_dir" ] || [ -z "$branch" ]; then
  echo "Usage: autopull.sh <repo_dir> <branch>" >&2
  exit 2
fi

if [ -n "${PULL_LOG_PATH:-}" ]; then
  mkdir -p "$(dirname "$PULL_LOG_PATH")"
  exec >>"$PULL_LOG_PATH" 2>&1
fi

git_bin="${GIT_BIN:-git}"
if ! command -v "$git_bin" >/dev/null 2>&1; then
  log "ERROR: git not found: ${git_bin}"
  exit 1
fi

if [ ! -d "${repo_dir}/.git" ]; then
  log "ERROR: not a git repo: ${repo_dir}"
  exit 1
fi

cd "$repo_dir"

current_branch="$($git_bin rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ -z "$current_branch" ]; then
  log "ERROR: unable to resolve current branch"
  exit 1
fi

if [ "$current_branch" != "$branch" ]; then
  log "Skip: branch ${current_branch} != ${branch}"
  exit 0
fi

if [ -n "$($git_bin status --porcelain 2>/dev/null)" ]; then
  log "Skip: dirty working tree"
  exit 0
fi

log "Pulling updates on ${current_branch}"
$git_bin pull --ff-only
log "Done"
