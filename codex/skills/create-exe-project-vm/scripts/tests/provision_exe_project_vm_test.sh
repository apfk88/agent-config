#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../bootstrap_exe_project_credentials.sh
source "$SCRIPT_DIR/bootstrap_exe_project_credentials.sh"
# shellcheck source=../provision_exe_project_vm.sh
source "$SCRIPT_DIR/provision_exe_project_vm.sh"
# shellcheck source=../register_codex_remote_project.sh
source "$SCRIPT_DIR/register_codex_remote_project.sh"

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
assert_eq "integrations add github --name=demo" \
  "$(exe_command_string integrations add github --name=demo)" \
  "builds exe.dev API command"
assert_eq "exe1.test" "$(extract_api_token '{"token":"exe1.test"}')" "extracts API token"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
SSH_CONFIG_PATH="$tmp_dir/config"
DRY_RUN=0

ensure_ssh_alias "proj-test" "proj-test.exe.xyz" >/dev/null
ensure_ssh_alias "proj-test" "proj-test.exe.xyz" >/dev/null

assert_eq "proj-test.exe.xyz" "$(host_block_hostname proj-test "$SSH_CONFIG_PATH")" "records SSH hostname"
assert_eq "1" "$(grep -c '^Host proj-test$' "$SSH_CONFIG_PATH")" "SSH alias is idempotent"

credential_config="$tmp_dir/credential-config"
printf 'Host *\n  IdentityAgent /tmp/1password.sock\n' > "$credential_config"
ensure_project_ssh_config "$credential_config" "$tmp_dir/id_exe_proj"
ensure_project_ssh_config "$credential_config" "$tmp_dir/id_exe_proj"
assert_eq "$BEGIN_MARKER" "$(head -n 1 "$credential_config")" "project credentials precede Host star"
assert_eq "1" "$(grep -cF "$BEGIN_MARKER" "$credential_config")" "credential block is idempotent"
assert_contains "$(ssh -F "$credential_config" -G proj-demo 2>/dev/null)" \
  "identityagent none" \
  "project alias bypasses SSH agent"

printf 'Host proj-broken\n  User exedev\n' >> "$SSH_CONFIG_PATH"
if (ensure_ssh_alias "proj-broken" "proj-broken.exe.xyz" >/dev/null 2>&1); then
  fail "rejects SSH alias without explicit HostName"
fi

dry_output="$({
  DRY_RUN=0
  main --dry-run --repo apfk88/demo --local-path /tmp/demo 'Demo App'
})"
assert_contains "$dry_output" "VM: proj-demo-app" "dry run names VM"
assert_contains "$dry_output" "--tag=proj\\,llm" "dry run tags VM"
assert_contains "$dry_output" "exe-api new" "dry run uses HTTPS control plane"
assert_contains "$dry_output" "tag:llm" "dry run checks LLM integration"
assert_contains "$dry_output" "proj-demo-app-repo" "dry run adds project integration"
assert_contains "$dry_output" "config.exe.toml" "dry run selects remote config"
assert_contains "$dry_output" "start Codex task" "dry run creates the first remote task"
assert_contains "$(<"$SCRIPT_DIR/provision_exe_project_vm.sh")" \
  "'Reply exactly REMOTE_CODEX_OK' </dev/null" \
  "remote Codex verification cannot consume bootstrap input"
assert_contains "$(<"$SCRIPT_DIR/provision_exe_project_vm.sh")" \
  "exeuntu configure codex" \
  "remote setup uses exeuntu Codex configuration"

app_config="$tmp_dir/codex-app/config.json"
mkdir -p "$(dirname "$app_config")"
printf '%s\n' '{"version":1,"sshConnectTimeoutSeconds":12,"remoteConnections":[{"sshAlias":"proj-existing","projects":[{"remotePath":"/home/exedev/src/existing"}]}]}' > "$app_config"
write_merged_config "$app_config" "proj-demo" "/home/exedev/src/demo" "demo"
write_merged_config "$app_config" "proj-demo" "/home/exedev/src/demo" "demo"
assert_eq "1" "$(jq '[.remoteConnections[] | select(.sshAlias == "proj-demo")] | length' "$app_config")" \
  "Codex app host registration is idempotent"
assert_eq "1" "$(jq '[.remoteConnections[] | select(.sshAlias == "proj-demo") | .projects[] | select(.remotePath == "/home/exedev/src/demo")] | length' "$app_config")" \
  "Codex app project registration is idempotent"
assert_eq "12" "$(jq -r '.sshConnectTimeoutSeconds' "$app_config")" \
  "Codex app registration preserves global settings"
assert_eq "demo" "$(jq -r '.remoteConnections[] | select(.sshAlias == "proj-demo") | .projects[0].label' "$app_config")" \
  "Codex app registration records the label"

fake_bin="$tmp_dir/fake-bin"
remote_dir="$tmp_dir/remote-project"
mkdir -p "$fake_bin" "$remote_dir"
cat > "$fake_bin/codex" <<'FAKE_CODEX'
#!/usr/bin/env bash
while IFS= read -r line; do
  method="$(printf '%s' "$line" | jq -r '.method // empty')"
  case "$method" in
    initialize) printf '%s\n' '{"id":1,"result":{"codexHome":"/tmp/codex"}}' ;;
    thread/start)
      printf '%s' "$line" | jq -e '.params.approvalPolicy == "never" and .params.sandbox == "danger-full-access"' >/dev/null || exit 1
      printf '%s\n' '{"id":2,"result":{"thread":{"id":"thread-test"}}}' ;;
    turn/start)
      printf '%s' "$line" | jq -e '.params.sandboxPolicy.type == "dangerFullAccess"' >/dev/null || exit 1
      printf '%s\n' '{"id":3,"result":{"turn":{"id":"turn-test"}}}' '{"method":"turn/completed","params":{"turn":{"id":"turn-test","status":"completed"}}}' ;;
    turn/interrupt) printf '%s\n' '{"id":4,"result":{}}' ;;
    thread/name/set) printf '%s\n' '{"id":5,"result":{}}' ;;
  esac
done
FAKE_CODEX
chmod +x "$fake_bin/codex"
task_output="$(PATH="$fake_bin:$PATH" bash "$SCRIPT_DIR/start_codex_remote_task.sh" --remote \
  "$remote_dir" "$(printf 'xtest prompt' | base64 | tr -d '\n')" "$(printf 'test title' | base64 | tr -d '\n')")"
assert_eq "thread-test" "$(printf '%s' "$task_output" | jq -r '.thread_id')" \
  "remote task uses the VM app-server"
assert_eq "completed" "$(printf '%s' "$task_output" | jq -r '.status')" \
  "remote task waits for completion"
ready_output="$(PATH="$fake_bin:$PATH" bash "$SCRIPT_DIR/start_codex_remote_task.sh" --remote \
  "$remote_dir" "$(printf 'x' | base64 | tr -d '\n')" "$(printf 'ready title' | base64 | tr -d '\n')")"
assert_eq "ready" "$(printf '%s' "$ready_output" | jq -r '.status')" \
  "remote task can be created without a model call"
assert_eq "turn-test" "$(printf '%s' "$ready_output" | jq -r '.turn_id')" \
  "ready remote task records its handoff marker"

printf 'All provision_exe_project_vm tests passed\n'
