#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../provision_exe_project_vm.sh
source "$SCRIPT_DIR/provision_exe_project_vm.sh"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  [ "$expected" = "$actual" ] || fail "$label: expected '$expected', got '$actual'"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  printf '%s' "$haystack" | grep -Fq -- "$needle" || fail "$label: missing '$needle'"
}

assert_eq "my-project" "$(normalize_slug 'My Project')" "normalizes project slug"
assert_eq "my-project" "$(normalize_slug 'proj-My Project')" "removes proj prefix"
assert_eq "project.int.exe.xyz/apfk88/demo" \
  "$(qualified_gh_repo project.int.exe.xyz apfk88/demo)" \
  "qualifies GH_REPO for custom host"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
SSH_CONFIG_PATH="$tmp_dir/config"
DRY_RUN=0

ensure_ssh_alias "proj-test" "proj-test.exe.xyz" >/dev/null
ensure_ssh_alias "proj-test" "proj-test.exe.xyz" >/dev/null

assert_eq "proj-test.exe.xyz" "$(host_block_hostname proj-test "$SSH_CONFIG_PATH")" "records SSH hostname"
assert_eq "1" "$(grep -c '^Host proj-test$' "$SSH_CONFIG_PATH")" "SSH alias is idempotent"

printf 'Host proj-broken\n  User exedev\n' >> "$SSH_CONFIG_PATH"
if (ensure_ssh_alias "proj-broken" "proj-broken.exe.xyz" >/dev/null 2>&1); then
  fail "rejects SSH alias without explicit HostName"
fi

dry_output="$({
  DRY_RUN=0
  main --dry-run --repo apfk88/demo --local-path /tmp/demo 'Demo App'
})"
assert_contains "$dry_output" "VM: proj-demo-app" "dry run names VM"
assert_contains "$dry_output" "--tag=proj" "dry run tags VM"
assert_contains "$dry_output" "proj-demo-app-repo" "dry run adds project integration"
assert_contains "$dry_output" "config.exe.toml" "dry run selects remote config"

printf 'All provision_exe_project_vm tests passed\n'
