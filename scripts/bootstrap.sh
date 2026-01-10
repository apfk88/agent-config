#!/usr/bin/env bash
set -euo pipefail

# ---------------- defaults ----------------
REPO_SLUG_DEFAULT="apfk88/agent-config"
REPO_PARENT_DEFAULT="$HOME/repos"
REPO_NAME_DEFAULT="agent-config"
REPO_DIR_DEFAULT="${REPO_PARENT_DEFAULT}/${REPO_NAME_DEFAULT}"

# Repo contains <agent>/AGENTS.md and <agent>/skills/
AGENT_SUBDIR_DEFAULT="codex"

# Agent config target dir (defaults to Codex)
AGENT_DIR_DEFAULT="$HOME/.codex"
AGENT_FILE_DEFAULT="AGENTS.md"
AGENT_LINK_DEFAULT="agents.md"
AGENT_SKILLS_DIR_DEFAULT="skills"
AGENT_SKILLS_LINK_DEFAULT="skills"

BRANCH_DEFAULT="main"
PULL_EVERY_MINUTES_DEFAULT="60"
CRON_TAG="agent-config-autopull"
# ------------------------------------------

log() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing required command: $1"; exit 1; }
}

backup_if_exists() {
  local path="$1"
  if [ -e "$path" ] || [ -L "$path" ]; then
    local ts
    ts="$(date +%s)"
    mv "$path" "${path}.bak.${ts}"
    log "Backed up $path -> ${path}.bak.${ts}"
  fi
}

repo_root_if_inside() {
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
    return 0
  fi
  return 1
}

ensure_repo_present() {
  local repo_dir="$1"
  local slug="${AGENT_CONFIG_REPO_SLUG:-$REPO_SLUG_DEFAULT}"

  if [ -d "${repo_dir}/.git" ]; then
    log "Repo present at ${repo_dir}"
    return 0
  fi

  mkdir -p "$(dirname "$repo_dir")"

  log "Cloning via gh: ${slug} -> ${repo_dir}"
  gh repo clone "${slug}" "${repo_dir}"
}

validate_layout() {
  local repo_dir="$1"
  local agent_subdir="${AGENT_SUBDIR:-${CODEX_SUBDIR:-$AGENT_SUBDIR_DEFAULT}}"
  local agent_path="${repo_dir}/${agent_subdir}"
  local agent_file="${AGENT_FILE:-$AGENT_FILE_DEFAULT}"
  local skills_dir="${AGENT_SKILLS_DIR:-$AGENT_SKILLS_DIR_DEFAULT}"

  [ -d "$agent_path" ] || { err "Expected folder: ${agent_path}"; exit 1; }
  [ -f "${agent_path}/${agent_file}" ] || { err "Expected file: ${agent_path}/${agent_file}"; exit 1; }
  if [ -n "$skills_dir" ]; then
    [ -d "${agent_path}/${skills_dir}" ] || { err "Expected folder: ${agent_path}/${skills_dir}"; exit 1; }
  fi
}

install_symlinks() {
  local repo_dir="$1"
  local agent_subdir="${AGENT_SUBDIR:-${CODEX_SUBDIR:-$AGENT_SUBDIR_DEFAULT}}"
  local agent_path="${repo_dir}/${agent_subdir}"
  local agent_dir="${AGENT_DIR:-${CODEX_DIR:-$AGENT_DIR_DEFAULT}}"
  local agent_file="${AGENT_FILE:-$AGENT_FILE_DEFAULT}"
  local agent_link="${AGENT_LINK:-$AGENT_LINK_DEFAULT}"
  local skills_dir="${AGENT_SKILLS_DIR:-$AGENT_SKILLS_DIR_DEFAULT}"
  local skills_link="${AGENT_SKILLS_LINK:-$AGENT_SKILLS_LINK_DEFAULT}"

  mkdir -p "$agent_dir"

  backup_if_exists "${agent_dir}/${agent_link}"
  if [ -n "$skills_dir" ]; then
    backup_if_exists "${agent_dir}/${skills_link}"
  fi

  ln -sfn "${agent_path}/${agent_file}" "${agent_dir}/${agent_link}"
  if [ -n "$skills_dir" ]; then
    ln -sfn "${agent_path}/${skills_dir}" "${agent_dir}/${skills_link}"
  fi

  log "Symlinks set:"
  log "  ${agent_dir}/${agent_link} -> ${agent_path}/${agent_file}"
  if [ -n "$skills_dir" ]; then
    log "  ${agent_dir}/${skills_link} -> ${agent_path}/${skills_dir}"
  fi
}

install_cron_autopull() {
  local repo_dir="$1"
  local minutes="${PULL_EVERY_MINUTES:-$PULL_EVERY_MINUTES_DEFAULT}"
  local branch="${AGENT_CONFIG_BRANCH:-$BRANCH_DEFAULT}"

  # Pull only if:
  # - on the expected branch
  # - working tree is clean (prevents surprises while editing)
  local cron_line
  cron_line="*/${minutes} * * * * cd \"${repo_dir}\" && [ \"\$(git rev-parse --abbrev-ref HEAD 2>/dev/null)\" = \"${branch}\" ] && [ -z \"\$(git status --porcelain 2>/dev/null)\" ] && git pull --ff-only >/dev/null 2>&1 # ${CRON_TAG}"

  local current
  current="$(crontab -l 2>/dev/null || true)"

  local filtered
  filtered="$(printf '%s\n' "$current" | grep -v "${CRON_TAG}" || true)"

  printf '%s\n%s\n' "$filtered" "$cron_line" | crontab -

  log "Cron installed/updated:"
  log "  ${cron_line}"
}

main() {
  need_cmd gh
  need_cmd git
  need_cmd ln
  need_cmd crontab
  need_cmd grep
  need_cmd mv
  need_cmd date

  local repo_dir="${AGENT_CONFIG_REPO_DIR:-$REPO_DIR_DEFAULT}"

  # If running from inside the repo, prefer that location.
  local inside_root=""
  if inside_root="$(repo_root_if_inside)"; then
    repo_dir="$inside_root"
    log "Detected repo root from current directory: ${repo_dir}"
  fi

  ensure_repo_present "$repo_dir"
  validate_layout "$repo_dir"
  install_symlinks "$repo_dir"
  install_cron_autopull "$repo_dir"

  log "Done."
}

main "$@"
