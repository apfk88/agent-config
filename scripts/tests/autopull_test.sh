#!/usr/bin/env bash
set -euo pipefail

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

repo_dir="$tmp_dir/repo"
mkdir -p "$repo_dir/.git"

calls_file="$tmp_dir/calls"
git_stub="$tmp_dir/git"

cat <<'STUB' > "$git_stub"
#!/usr/bin/env bash
set -euo pipefail
cmd="${1:-}"
shift || true
case "$cmd" in
  rev-parse)
    echo "${GIT_REV_BRANCH:-main}"
    ;;
  status)
    printf '%s' "${GIT_STATUS:-}"
    ;;
  pull)
    echo "pull" >>"${GIT_CALLS}"
    ;;
  *)
    echo "unknown git cmd: ${cmd}" >&2
    exit 1
    ;;
  esac
STUB
chmod +x "$git_stub"

export GIT_BIN="$git_stub"
export GIT_CALLS="$calls_file"

# Case 1: branch mismatch -> skip pull
: >"$calls_file"
GIT_REV_BRANCH="feature" GIT_STATUS="" PULL_LOG_PATH="" \
  bash scripts/autopull.sh "$repo_dir" "main"
if [ -s "$calls_file" ]; then
  echo "FAIL: expected no pull on branch mismatch" >&2
  exit 1
fi

# Case 2: dirty tree -> skip pull
: >"$calls_file"
GIT_REV_BRANCH="main" GIT_STATUS=" M file" PULL_LOG_PATH="" \
  bash scripts/autopull.sh "$repo_dir" "main"
if [ -s "$calls_file" ]; then
  echo "FAIL: expected no pull on dirty tree" >&2
  exit 1
fi

# Case 3: clean tree -> pull
: >"$calls_file"
GIT_REV_BRANCH="main" GIT_STATUS="" PULL_LOG_PATH="" \
  bash scripts/autopull.sh "$repo_dir" "main"
if ! grep -q "pull" "$calls_file"; then
  echo "FAIL: expected pull on clean tree" >&2
  exit 1
fi

printf '%s\n' "ok"
