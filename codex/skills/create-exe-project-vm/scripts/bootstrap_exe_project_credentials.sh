#!/usr/bin/env bash
set -euo pipefail

EXE_PROJECT_KEY_PATH="${EXE_PROJECT_KEY_PATH:-$HOME/.ssh/id_exe_proj}"
EXE_API_TOKEN_PATH="${EXE_API_TOKEN_PATH:-$HOME/.config/exe/project-vm.token}"
SSH_CONFIG_PATH="${SSH_CONFIG_PATH:-$HOME/.ssh/config}"
EXE_API_URL="${EXE_API_URL:-https://exe.dev/exec}"
TOKEN_COMMANDS="whoami,ls,new,integrations list,integrations add,integrations attach"
BEGIN_MARKER="# BEGIN create-exe-project-vm credentials"
END_MARKER="# END create-exe-project-vm credentials"

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

extract_api_token() {
  local response="$1" token
  token="$(printf '%s' "$response" | jq -r \
    '.token // .api_key // .apiKey // .bearer_token // .bearer // empty' 2>/dev/null || true)"
  if [ -z "$token" ] && [[ "$response" == exe1.* ]]; then
    token="$response"
  fi
  [ -n "$token" ] || return 1
  printf '%s' "$token"
}

ensure_project_ssh_config() {
  local config="$1" key_path="$2" config_dir temp
  config_dir="$(dirname "$config")"
  mkdir -p "$config_dir"
  touch "$config"
  chmod 600 "$config"
  temp="$(mktemp "${config}.XXXXXX")"

  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin { skipping = 1; next }
    $0 == end { skipping = 0; next }
    !skipping { print }
  ' "$config" > "$temp"

  {
    printf '%s\n' "$BEGIN_MARKER"
    printf 'Host proj-* proj-*.exe.xyz\n'
    printf '  IdentityAgent none\n'
    printf '  IdentitiesOnly yes\n'
    printf '  IdentityFile %s\n' "$key_path"
    printf '%s\n\n' "$END_MARKER"
    sed '/./,$!d' "$temp"
  } > "${temp}.new"

  mv "${temp}.new" "$config"
  rm -f "$temp"
  chmod 600 "$config"
}

store_token() {
  local token="$1" destination="$2" directory temp
  directory="$(dirname "$destination")"
  mkdir -p "$directory"
  temp="$(mktemp "${directory}/project-vm.token.XXXXXX")"
  chmod 600 "$temp"
  printf '%s\n' "$token" > "$temp"
  mv "$temp" "$destination"
  chmod 600 "$destination"
}

verify_token() {
  local token="$1"
  curl --fail-with-body --silent --show-error \
    --request POST \
    --header "Authorization: Bearer ${token}" \
    --data-binary whoami \
    "$EXE_API_URL" >/dev/null
}

main() {
  need_cmd ssh
  need_cmd ssh-keygen
  need_cmd jq
  need_cmd curl

  mkdir -p "$(dirname "$EXE_PROJECT_KEY_PATH")"
  chmod 700 "$(dirname "$EXE_PROJECT_KEY_PATH")"

  local key_created=0
  if [ ! -f "$EXE_PROJECT_KEY_PATH" ]; then
    ssh-keygen -q -t ed25519 -N '' \
      -C "codex-exe-proj-$(hostname -s)" \
      -f "$EXE_PROJECT_KEY_PATH"
    chmod 600 "$EXE_PROJECT_KEY_PATH"
    chmod 644 "${EXE_PROJECT_KEY_PATH}.pub"
    key_created=1
    log "Created project-only SSH key: ${EXE_PROJECT_KEY_PATH}"
  elif [ ! -f "${EXE_PROJECT_KEY_PATH}.pub" ]; then
    ssh-keygen -y -f "$EXE_PROJECT_KEY_PATH" > "${EXE_PROJECT_KEY_PATH}.pub"
    chmod 644 "${EXE_PROJECT_KEY_PATH}.pub"
  fi

  if [ "$key_created" -eq 1 ]; then
    log "Registering the #proj key with exe.dev; 1Password may request one authorization."
    ssh -o BatchMode=yes exe.dev ssh-key add --tag=proj < "${EXE_PROJECT_KEY_PATH}.pub" >/dev/null
  fi

  if [ ! -s "$EXE_API_TOKEN_PATH" ]; then
    local response token token_command
    token_command="ssh-key generate-api-key --label=codex-project-vm '--cmds=${TOKEN_COMMANDS}' --exp=1y --json"
    response="$(ssh -o BatchMode=yes exe.dev "$token_command")"
    token="$(extract_api_token "$response")" || \
      die "exe.dev returned an unrecognized API-token response"
    verify_token "$token"
    store_token "$token" "$EXE_API_TOKEN_PATH"
    log "Stored restricted exe.dev token: ${EXE_API_TOKEN_PATH}"
  else
    local token
    IFS= read -r token < "$EXE_API_TOKEN_PATH"
    chmod 600 "$EXE_API_TOKEN_PATH"
    verify_token "$token"
    log "Existing exe.dev token verified: ${EXE_API_TOKEN_PATH}"
  fi

  ensure_project_ssh_config "$SSH_CONFIG_PATH" "$EXE_PROJECT_KEY_PATH"
  log "Configured project VM SSH to bypass 1Password: ${SSH_CONFIG_PATH}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
