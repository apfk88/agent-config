#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=0
SKIP_CODEX_LOGIN=0
REPO=""
LOCAL_PATH=""
AGENT_CONFIG_REPO="${AGENT_CONFIG_REPO:-apfk88/agent-config}"
SSH_CONFIG_PATH="${SSH_CONFIG_PATH:-$HOME/.ssh/config}"

usage() {
  cat <<'USAGE'
Usage: provision_exe_project_vm.sh [options] <project-slug>

Options:
  --repo OWNER/REPO       Existing GitHub repository (required)
  --local-path PATH       Existing laptop clone (required)
  --dry-run               Print the plan without changing local or remote state
  --skip-codex-login      Skip device auth; intended only for disposable smoke tests
  -h, --help              Show this help

Creates or reuses proj-<slug>, tags it proj, attaches restricted exe.dev
GitHub integrations for the project and agent-config, bootstraps remote Codex
configuration, and clones the project to ~/src/<repo>.
USAGE
}

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

normalize_slug() {
  local value="$1"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  value="${value#proj-}"
  value="$(printf '%.48s' "$value")"
  value="${value%-}"
  [ -n "$value" ] || return 1
  printf '%s' "$value"
}

validate_repo() {
  [[ "$1" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die "Invalid GitHub repository: $1"
}

print_cmd() {
  printf '+ '
  printf '%q ' "$@"
  printf '\n'
}

run_cmd() {
  print_cmd "$@"
  if [ "$DRY_RUN" -eq 0 ]; then
    "$@"
  fi
}

host_block_hostname() {
  local alias="$1"
  local config="$2"
  awk -v wanted="$alias" '
    tolower($1) == "host" {
      active = 0
      for (i = 2; i <= NF; i++) if ($i == wanted) active = 1
      next
    }
    active && tolower($1) == "hostname" { print $2; exit }
  ' "$config"
}

ensure_ssh_alias() {
  local alias="$1"
  local hostname="$2"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] ensure SSH alias ${alias} -> ${hostname} in ${SSH_CONFIG_PATH}"
    return 0
  fi

  mkdir -p "$(dirname "$SSH_CONFIG_PATH")"
  touch "$SSH_CONFIG_PATH"
  chmod 600 "$SSH_CONFIG_PATH"

  local configured=""
  configured="$(host_block_hostname "$alias" "$SSH_CONFIG_PATH")"
  if [ -n "$configured" ]; then
    [ "$configured" = "$hostname" ] || die "SSH alias ${alias} already points to ${configured}"
    log "SSH alias already configured: ${alias}"
    return 0
  fi

  if awk -v wanted="$alias" '
    tolower($1) == "host" {
      for (i = 2; i <= NF; i++) if ($i == wanted) found = 1
    }
    END { exit(found ? 0 : 1) }
  ' "$SSH_CONFIG_PATH"; then
    die "SSH alias ${alias} exists without an explicit HostName"
  fi

  {
    printf '\n# BEGIN create-exe-project-vm %s\n' "$alias"
    printf 'Host %s\n' "$alias"
    printf '  HostName %s\n' "$hostname"
    printf '  User exedev\n'
    printf '# END create-exe-project-vm %s\n' "$alias"
  } >> "$SSH_CONFIG_PATH"
  log "Added SSH alias: ${alias} -> ${hostname}"
}

local_repo_slug() {
  local path="$1"
  local origin
  origin="$(git -C "$path" remote get-url origin 2>/dev/null || true)"
  case "$origin" in
    https://github.com/*)
      origin="${origin#https://github.com/}"
      ;;
    git@github.com:*)
      origin="${origin#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      origin="${origin#ssh://git@github.com/}"
      ;;
    *)
      return 1
      ;;
  esac
  printf '%s' "${origin%.git}"
}

preflight() {
  need_cmd ssh
  need_cmd jq
  need_cmd git
  need_cmd gh
  need_cmd sed
  need_cmd awk
  need_cmd base64

  if [ "$DRY_RUN" -eq 1 ]; then
    return 0
  fi

  ssh -o BatchMode=yes -o ConnectTimeout=10 exe.dev whoami >/dev/null
  gh auth status --hostname github.com >/dev/null
  gh repo view "$REPO" --json nameWithOwner >/dev/null
  gh repo view "$AGENT_CONFIG_REPO" --json nameWithOwner >/dev/null

  [ -d "$LOCAL_PATH/.git" ] || die "Local clone is missing: ${LOCAL_PATH}"
  local actual_repo=""
  actual_repo="$(local_repo_slug "$LOCAL_PATH" || true)"
  [ "$actual_repo" = "$REPO" ] || die "${LOCAL_PATH} origin is ${actual_repo:-not GitHub}; expected ${REPO}"
}

ensure_vm() {
  local vm="$1"
  if [ "$DRY_RUN" -eq 1 ]; then
    print_cmd ssh exe.dev new "--name=${vm}" --tag=proj "--comment=repo:${REPO}" --json
    return 0
  fi

  local inventory existing tags
  inventory="$(ssh exe.dev ls --json)"
  existing="$(printf '%s' "$inventory" | jq -r --arg vm "$vm" '.vms[]? | select(.vm_name == $vm) | .vm_name')"
  if [ -z "$existing" ]; then
    run_cmd ssh exe.dev new "--name=${vm}" --tag=proj "--comment=repo:${REPO}" --json
    return 0
  fi

  tags="$(printf '%s' "$inventory" | jq -r --arg vm "$vm" '.vms[]? | select(.vm_name == $vm) | (.tags // [])[]')"
  printf '%s\n' "$tags" | grep -Fxq proj || die "Existing VM ${vm} is not tagged proj; refusing to reuse it"
  log "Reusing existing project VM: ${vm}"
}

wait_for_ssh() {
  local destination="$1"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] wait for SSH at ${destination}"
    return 0
  fi

  local attempt
  for attempt in $(seq 1 30); do
    if ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "$destination" true >/dev/null 2>&1; then
      log "SSH ready: ${destination}"
      return 0
    fi
    sleep 2
  done
  die "Timed out waiting for SSH: ${destination}"
}

ensure_integration() {
  local name="$1"
  local repository="$2"
  local vm="$3"
  local act_as_user="$4"

  if [ "$DRY_RUN" -eq 1 ]; then
    local args=(ssh exe.dev integrations add github "--name=${name}" "--repository=${repository}" "--attach=vm:${vm}")
    [ "$act_as_user" = "yes" ] && args+=(--act-as-user)
    print_cmd "${args[@]}"
    return 0
  fi

  local integrations existing type configured_repo attachment
  integrations="$(ssh exe.dev integrations list --json)"
  existing="$(printf '%s' "$integrations" | jq -c --arg name "$name" '.[]? | select(.name == $name)')"
  if [ -z "$existing" ]; then
    local args=(ssh exe.dev integrations add github "--name=${name}" "--repository=${repository}" "--attach=vm:${vm}")
    [ "$act_as_user" = "yes" ] && args+=(--act-as-user)
    run_cmd "${args[@]}"
    return 0
  fi

  type="$(printf '%s' "$existing" | jq -r '.type // ""')"
  configured_repo="$(printf '%s' "$existing" | jq -r '.config.repository // .repository // ""')"
  [ "$type" = github ] || die "Integration ${name} exists with type ${type}"
  if [ -n "$configured_repo" ] && [ "$configured_repo" != "$repository" ]; then
    die "Integration ${name} targets ${configured_repo}, expected ${repository}"
  fi

  attachment="vm:${vm}"
  if ! printf '%s' "$existing" | jq -e --arg attachment "$attachment" '(.attachments // []) | index($attachment) != null' >/dev/null; then
    run_cmd ssh exe.dev integrations attach "$name" "$attachment"
  else
    log "Integration already attached: ${name}"
  fi
}

encode_base64() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

prepare_remote() {
  local destination="$1"
  local vm="$2"
  local project_integration="$3"
  local config_integration="$4"
  local repo_name="$5"
  local project_host="${project_integration}.int.exe.xyz"
  local config_url="https://${config_integration}.int.exe.xyz/${AGENT_CONFIG_REPO}.git"
  local project_url="https://${project_host}/${REPO}.git"
  local git_name git_email name_b64 email_b64

  git_name="$(git config --global user.name 2>/dev/null || true)"
  git_email="$(git config --global user.email 2>/dev/null || true)"
  name_b64="$(encode_base64 "$git_name")"
  email_b64="$(encode_base64 "$git_email")"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] update Codex on ${destination}"
    log "[dry-run] clone ${AGENT_CONFIG_REPO} to ~/repos/agent-config and run bootstrap with config.exe.toml"
    log "[dry-run] clone ${REPO} to ~/src/${repo_name}"
    log "[dry-run] configure GH_HOST=${project_host} and GH_REPO=${REPO}"
    return 0
  fi

  run_cmd ssh "$destination" 'sudo exeuntu update codex && codex --version'

  ssh "$destination" bash -s -- \
    "$config_url" "$project_url" "$project_host" "$REPO" "$repo_name" "$vm" "$name_b64" "$email_b64" <<'REMOTE'
set -euo pipefail
config_url="$1"
project_url="$2"
project_host="$3"
repository="$4"
repo_name="$5"
vm="$6"
name_b64="$7"
email_b64="$8"
config_dir="$HOME/repos/agent-config"
project_dir="$HOME/src/$repo_name"

mkdir -p "$HOME/repos" "$HOME/src"

if [ -d "$config_dir/.git" ]; then
  git -C "$config_dir" pull --ff-only
else
  git clone "$config_url" "$config_dir"
fi

AGENT_CONFIG_FILE="config.exe.toml" DEV_DIR="$HOME/src" "$config_dir/scripts/bootstrap.sh"

if [ -d "$project_dir/.git" ]; then
  actual_origin="$(git -C "$project_dir" remote get-url origin)"
  [ "$actual_origin" = "$project_url" ] || {
    echo "ERROR: $project_dir origin is $actual_origin; expected $project_url" >&2
    exit 1
  }
  git -C "$project_dir" fetch origin
else
  git clone "$project_url" "$project_dir"
fi

profile="$HOME/.profile"
marker="# create-exe-project-vm: $vm"
touch "$profile"
if ! grep -Fq "$marker" "$profile"; then
  {
    printf '\n%s\n' "$marker"
    printf 'export GH_HOST=%q\n' "$project_host"
    printf 'export GH_REPO=%q\n' "$repository"
  } >> "$profile"
fi

git_name="$(printf '%s' "$name_b64" | base64 -d)"
git_email="$(printf '%s' "$email_b64" | base64 -d)"
[ -z "$git_name" ] || git config --global user.name "$git_name"
[ -z "$git_email" ] || git config --global user.email "$git_email"
REMOTE
}

authenticate_codex() {
  local destination="$1"
  if [ "$DRY_RUN" -eq 1 ]; then
    print_cmd ssh -tt "$destination" codex login --device-auth
    return 0
  fi
  if ssh "$destination" codex login status >/dev/null 2>&1; then
    log "Codex already authenticated on ${destination}"
    return 0
  fi
  if [ "$SKIP_CODEX_LOGIN" -eq 1 ]; then
    log "Skipping Codex login for smoke test"
    return 0
  fi
  ssh -tt "$destination" codex login --device-auth
}

verify_remote() {
  local destination="$1"
  local project_integration="$2"
  local repo_name="$3"
  local project_host="${project_integration}.int.exe.xyz"

  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] verify Codex, app-server, symlinks, Git, and restricted gh access on ${destination}"
    return 0
  fi

  ssh "$destination" bash -s -- "$project_host" "$REPO" "$repo_name" "$SKIP_CODEX_LOGIN" <<'REMOTE'
set -euo pipefail
project_host="$1"
repository="$2"
repo_name="$3"
skip_login="$4"

codex --version
codex app-server --help >/dev/null
[ "$skip_login" = 1 ] || codex login status
[ -L "$HOME/.codex/agents.md" ]
[ -L "$HOME/.codex/config.toml" ]
[ -L "$HOME/.codex/skills" ]
[ "$(readlink "$HOME/.codex/config.toml")" = "$HOME/repos/agent-config/codex/config.exe.toml" ]
GH_HOST="$project_host" GH_REPO="$repository" gh repo view --json nameWithOwner >/dev/null
git -C "$HOME/src/$repo_name" status --short --branch
printf 'Remote verification passed\n'
REMOTE
}

main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo)
        REPO="${2:-}"
        shift 2
        ;;
      --local-path)
        LOCAL_PATH="${2:-}"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --skip-codex-login)
        SKIP_CODEX_LOGIN=1
        shift
        ;;
      -h|--help)
        usage
        return 0
        ;;
      --*)
        die "Unknown option: $1"
        ;;
      *)
        break
        ;;
    esac
  done

  [ "$#" -eq 1 ] || { usage >&2; die "Project slug is required"; }
  [ -n "$REPO" ] || die "--repo is required"
  [ -n "$LOCAL_PATH" ] || die "--local-path is required"
  validate_repo "$REPO"
  validate_repo "$AGENT_CONFIG_REPO"

  local slug vm hostname destination repo_name project_integration config_integration
  slug="$(normalize_slug "$1")" || die "Project slug must contain letters or numbers"
  vm="proj-${slug}"
  hostname="${vm}.exe.xyz"
  destination="$hostname"
  repo_name="${REPO##*/}"
  project_integration="${vm}-repo"
  config_integration="${vm}-config"

  preflight
  log "Project: ${REPO}"
  log "VM: ${vm}"
  ensure_vm "$vm"
  ensure_ssh_alias "$vm" "$hostname"
  wait_for_ssh "$destination"
  ensure_integration "$project_integration" "$REPO" "$vm" yes
  ensure_integration "$config_integration" "$AGENT_CONFIG_REPO" "$vm" no
  prepare_remote "$destination" "$vm" "$project_integration" "$config_integration" "$repo_name"
  authenticate_codex "$destination"
  verify_remote "$destination" "$project_integration" "$repo_name"

  jq -n \
    --arg vm "$vm" \
    --arg ssh_alias "$vm" \
    --arg repo "$REPO" \
    --arg local_path "$LOCAL_PATH" \
    --arg remote_path "/home/exedev/src/${repo_name}" \
    --arg github_host "${project_integration}.int.exe.xyz" \
    '{vm: $vm, ssh_alias: $ssh_alias, repo: $repo, local_path: $local_path, remote_path: $remote_path, github_host: $github_host}'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
