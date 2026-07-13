#!/usr/bin/env bash
set -euo pipefail

SSH_ALIAS=""
REMOTE_PATH=""
TITLE=""
PROMPT=""
DRY_RUN=0
REMOTE_TASK_SERVER_PID=""
REMOTE_TASK_TRANSPORT_DIR=""

usage() {
  cat <<'USAGE'
Usage: start_codex_remote_task.sh [options]

Options:
  --ssh-alias ALIAS     Concrete Codex SSH host alias
  --remote-path PATH    Remote project directory
  --title TITLE         Task title shown in Codex desktop
  --prompt PROMPT       Optional initial task request
  --dry-run             Print the plan without starting a task
  -h, --help            Show this help

Starts a persistent task with the VM's Codex app-server policy. The task is
discoverable by Codex desktop when the managed SSH connection is applied.
USAGE
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

encode_base64() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

remote_main() {
  local remote_path="$1" prompt title prompt_payload
  prompt_payload="$(printf '%s' "$2" | base64 -d)"
  prompt="${prompt_payload#x}"
  title="$(printf '%s' "$3" | base64 -d)"
  command -v codex >/dev/null 2>&1 || die "Codex is unavailable on the VM"
  command -v jq >/dev/null 2>&1 || die "jq is unavailable on the VM"
  [ -d "$remote_path" ] || die "Remote project is missing: $remote_path"

  local transport_dir server_pid
  transport_dir="$(mktemp -d)"
  mkfifo "$transport_dir/in" "$transport_dir/out"
  codex app-server --stdio < "$transport_dir/in" > "$transport_dir/out" &
  server_pid="$!"
  REMOTE_TASK_SERVER_PID="$server_pid"
  REMOTE_TASK_TRANSPORT_DIR="$transport_dir"
  exec 3>"$transport_dir/in" 4<"$transport_dir/out"
  cleanup_remote_task() {
    exec 3>&- || true
    exec 4<&- || true
    [ -z "$REMOTE_TASK_SERVER_PID" ] || kill "$REMOTE_TASK_SERVER_PID" 2>/dev/null || true
    [ -z "$REMOTE_TASK_SERVER_PID" ] || wait "$REMOTE_TASK_SERVER_PID" 2>/dev/null || true
    [ -z "$REMOTE_TASK_TRANSPORT_DIR" ] || rm -rf "$REMOTE_TASK_TRANSPORT_DIR"
    return 0
  }
  trap cleanup_remote_task EXIT

  send_request() { printf '%s\n' "$1" >&3; }
  wait_for_id() {
    local wanted="$1" line id
    while IFS= read -r line <&4; do
      id="$(printf '%s' "$line" | jq -r '.id // empty' 2>/dev/null || true)"
      if [ "$id" = "$wanted" ]; then
        printf '%s' "$line"
        return 0
      fi
    done
    return 1
  }
  require_result() {
    local response="$1"
    if ! printf '%s' "$response" | jq -e 'has("result")' >/dev/null; then
      printf '%s\n' "$response" | jq -r '.error.message // "Unknown app-server error"' >&2
      return 1
    fi
  }

  local response thread_id turn_id="" line method completed_turn status="ready"
  send_request "$(jq -nc '{id:1,method:"initialize",params:{clientInfo:{name:"create-exe-project-vm",version:"1.0.0"},capabilities:{experimentalApi:true}}}')"
  response="$(wait_for_id 1)"
  require_result "$response"
  send_request "$(jq -nc '{method:"initialized"}')"

  send_request "$(jq -nc --arg cwd "$remote_path" '{id:2,method:"thread/start",params:{cwd:$cwd,approvalPolicy:"never",approvalsReviewer:"user",sandbox:"danger-full-access",threadSource:"create-exe-project-vm"}}')"
  response="$(wait_for_id 2)"
  require_result "$response"
  thread_id="$(printf '%s' "$response" | jq -er '.result.thread.id')"

  local turn_prompt="$prompt"
  [ -n "$turn_prompt" ] || turn_prompt='Remote VM ready. Continue with your next instruction.'
  send_request "$(jq -nc --arg thread_id "$thread_id" --arg prompt "$turn_prompt" '{id:3,method:"turn/start",params:{threadId:$thread_id,input:[{type:"text",text:$prompt,text_elements:[]}],approvalPolicy:"never",approvalsReviewer:"user",sandboxPolicy:{type:"dangerFullAccess"}}}')"
  response="$(wait_for_id 3)"
  require_result "$response"
  turn_id="$(printf '%s' "$response" | jq -er '.result.turn.id')"
  if [ -z "$prompt" ]; then
    sleep 0.5
    send_request "$(jq -nc --arg thread_id "$thread_id" --arg turn_id "$turn_id" '{id:4,method:"turn/interrupt",params:{threadId:$thread_id,turnId:$turn_id}}')"
    response="$(wait_for_id 4)"
    if ! printf '%s' "$response" | jq -e 'has("result")' >/dev/null; then
      [ "$(printf '%s' "$response" | jq -r '.error.message // empty')" = 'no active turn to interrupt' ] || require_result "$response"
    fi
  else
    status=""
    while IFS= read -r line <&4; do
      method="$(printf '%s' "$line" | jq -r '.method // empty' 2>/dev/null || true)"
      [ "$method" = 'turn/completed' ] || continue
      completed_turn="$(printf '%s' "$line" | jq -r '.params.turn.id // empty')"
      [ "$completed_turn" = "$turn_id" ] || continue
      status="$(printf '%s' "$line" | jq -r '.params.turn.status // empty')"
      break
    done
    [ "$status" = completed ] || die "Remote Codex turn ended with status: ${status:-unknown}"
  fi

  send_request "$(jq -nc --arg thread_id "$thread_id" --arg title "$title" '{id:5,method:"thread/name/set",params:{threadId:$thread_id,name:$title}}')"
  response="$(wait_for_id 5)"
  require_result "$response"
  jq -nc --arg thread_id "$thread_id" --arg turn_id "$turn_id" --arg status "$status" \
    '{thread_id:$thread_id,turn_id:(if $turn_id == "" then null else $turn_id end),status:$status}'
  return 0
}

main() {
  if [ "${1:-}" = --remote ]; then
    [ "$#" -eq 4 ] || die "Invalid remote invocation"
    remote_main "$2" "$3" "$4"
    return
  fi

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --ssh-alias) SSH_ALIAS="${2:-}"; shift 2 ;;
      --remote-path) REMOTE_PATH="${2:-}"; shift 2 ;;
      --title) TITLE="${2:-}"; shift 2 ;;
      --prompt) PROMPT="${2:-}"; shift 2 ;;
      --dry-run) DRY_RUN=1; shift ;;
      -h|--help) usage; return ;;
      *) die "Unknown option: $1" ;;
    esac
  done

  [ -n "$SSH_ALIAS" ] || die "--ssh-alias is required"
  [ -n "$REMOTE_PATH" ] || die "--remote-path is required"
  [ -n "$TITLE" ] || die "--title is required"
  [[ "$SSH_ALIAS" =~ ^[A-Za-z0-9._-]+$ ]] || die "Invalid SSH alias: $SSH_ALIAS"
  [[ "$REMOTE_PATH" == /* ]] || die "--remote-path must be absolute"

  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] start Codex task %q at %s:%s\n' "$TITLE" "$SSH_ALIAS" "$REMOTE_PATH"
    return
  fi

  command -v ssh >/dev/null 2>&1 || die "Missing required command: ssh"
  command -v base64 >/dev/null 2>&1 || die "Missing required command: base64"
  ssh "$SSH_ALIAS" bash -s -- --remote "$REMOTE_PATH" \
    "$(encode_base64 "x${PROMPT}")" "$(encode_base64 "$TITLE")" < "$0"
}

if [ "${1:-}" = --remote ] || [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  main "$@"
fi
