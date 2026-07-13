#!/usr/bin/env bash
set -euo pipefail

SSH_ALIAS=""
REMOTE_PATH=""
LABEL=""
DRY_RUN=0
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CODEX_APP_CONFIG_PATH="${CODEX_APP_CONFIG_PATH:-$CODEX_HOME/codex-app/config.json}"
CODEX_APP_DEEP_LINK="${CODEX_APP_DEEP_LINK:-codex://codex-app/apply-config}"

usage() {
  cat <<'USAGE'
Usage: register_codex_remote_project.sh [options]

Options:
  --ssh-alias ALIAS     Concrete alias already present in ~/.ssh/config
  --remote-path PATH    Project directory on the SSH host
  --label LABEL         Project label shown in the Codex app
  --dry-run             Print the registration plan without writing or opening
  -h, --help            Show this help

Adds an SSH project to the Codex desktop app's managed config, enables automatic
connection, and asks a running app to apply the config through its deep link.
USAGE
}

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

validate_alias() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] || die "Invalid SSH alias: $1"
}

validate_existing_config() {
  local config="$1"
  jq -e '
    type == "object" and
    ((.version // 1) == 1) and
    ((.remoteConnections // []) | type == "array") and
    all((.remoteConnections // [])[];
      type == "object" and
      (.sshAlias | type == "string") and
      ((.projects // []) | type == "array"))
  ' "$config" >/dev/null || die "Invalid Codex app config: $config"
}

write_merged_config() {
  local config="$1" alias="$2" remote_path="$3" label="$4"
  local directory temp input
  directory="$(dirname "$config")"
  mkdir -p "$directory"
  temp="$(mktemp "${directory}/config.json.XXXXXX")"
  input="$config"

  if [ ! -e "$input" ]; then
    input="$(mktemp "${directory}/config.empty.XXXXXX")"
    printf '{"version":1,"remoteConnections":[]}\n' > "$input"
  else
    validate_existing_config "$input"
  fi

  jq \
    --arg alias "$alias" \
    --arg remote_path "$remote_path" \
    --arg label "$label" '
      .version = (.version // 1) |
      .remoteConnections = (
        (.remoteConnections // []) as $connections |
        ($connections | map(select(.sshAlias != $alias))) +
        [
          (($connections | map(select(.sshAlias == $alias)) | first) //
            {sshAlias: $alias, projects: []}) |
          .sshAlias = $alias |
          .projects = (
            ((.projects // []) | map(select(.remotePath != $remote_path))) +
            [
              ({remotePath: $remote_path} +
                (if $label == "" then {} else {label: $label} end))
            ]
          )
        ]
      )
    ' "$input" > "$temp"

  chmod 600 "$temp"
  mv "$temp" "$config"
  chmod 600 "$config"

  if [[ "$input" == "${directory}/config.empty."* ]]; then
    rm -f "$input"
  fi
}

apply_config() {
  need_cmd open
  open "$CODEX_APP_DEEP_LINK"
}

register_codex_remote_project_main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --ssh-alias)
        SSH_ALIAS="${2:-}"
        shift 2
        ;;
      --remote-path)
        REMOTE_PATH="${2:-}"
        shift 2
        ;;
      --label)
        LABEL="${2:-}"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h|--help)
        usage
        return 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done

  [ -n "$SSH_ALIAS" ] || die "--ssh-alias is required"
  [ -n "$REMOTE_PATH" ] || die "--remote-path is required"
  [[ "$REMOTE_PATH" == /* ]] || die "--remote-path must be absolute"
  validate_alias "$SSH_ALIAS"
  need_cmd jq

  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] register Codex SSH host ${SSH_ALIAS} with project ${REMOTE_PATH}"
    log "[dry-run] update ${CODEX_APP_CONFIG_PATH} and open ${CODEX_APP_DEEP_LINK}"
    return 0
  fi

  write_merged_config "$CODEX_APP_CONFIG_PATH" "$SSH_ALIAS" "$REMOTE_PATH" "$LABEL"
  apply_config
  log "Codex remote project registered: ${SSH_ALIAS}:${REMOTE_PATH}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  register_codex_remote_project_main "$@"
fi
