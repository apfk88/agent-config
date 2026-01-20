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
AGENT_CONFIG_FILE_DEFAULT="config.toml"
AGENT_CONFIG_LINK_DEFAULT="config.toml"
AGENT_SKILLS_DIR_DEFAULT="skills"
AGENT_SKILLS_LINK_DEFAULT="skills"
TIPS_FILE_DEFAULT="tips.md"
TIPS_LINK_DEFAULT="tips.md"
TMUX_CONF_SOURCE_DEFAULT="tmux.conf"
TMUX_CONF_LINK_DEFAULT="$HOME/.tmux.conf"
TM_BIN_DIR_DEFAULT="$HOME/.local/bin"
TM_LINK_DEFAULT="tm"
TM_SOURCE_DEFAULT="scripts/tm"
DEV_DIR_DEFAULT="$HOME/dev"

BRANCH_DEFAULT="main"
PULL_EVERY_MINUTES_DEFAULT="60"
CRON_TAG="agent-config-autopull"
PULL_LOG_PATH_DEFAULT="$HOME/.cache/agent-config/autopull.log"
# ------------------------------------------

log() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing required command: $1"; exit 1; }
}

warn_if_cron_inactive() {
  if [ "$(uname -s)" != "Linux" ]; then
    return 0
  fi
  if ! command -v systemctl >/dev/null 2>&1; then
    return 0
  fi
  if systemctl is-active --quiet cron.service 2>/dev/null; then
    return 0
  fi
  if systemctl is-active --quiet crond.service 2>/dev/null; then
    return 0
  fi
  log "WARN: cron service not active (cron.service/crond.service). Auto-pull may not run."
  log "      Enable with: sudo systemctl enable --now cron  # or crond"
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

link_points_to() {
  local link="$1"
  local target="$2"
  if [ -L "$link" ]; then
    [ "$(readlink "$link")" = "$target" ]
    return $?
  fi
  return 1
}

ensure_link() {
  local target="$1"
  local link="$2"
  if link_points_to "$link" "$target"; then
    log "Link ok: ${link}"
    return 0
  fi
  backup_if_exists "$link"
  ln -sfn "$target" "$link"
}

repo_root_if_inside() {
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
    return 0
  fi
  return 1
}

script_repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  local root
  root="$(cd "${script_dir}/.." && pwd -P)"
  if [ -d "${root}/.git" ]; then
    printf '%s' "$root"
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
  local config_file="${AGENT_CONFIG_FILE:-$AGENT_CONFIG_FILE_DEFAULT}"
  local skills_dir="${AGENT_SKILLS_DIR:-$AGENT_SKILLS_DIR_DEFAULT}"

  [ -d "$agent_path" ] || { err "Expected folder: ${agent_path}"; exit 1; }
  [ -f "${agent_path}/${agent_file}" ] || { err "Expected file: ${agent_path}/${agent_file}"; exit 1; }
  if [ -n "$config_file" ]; then
    [ -f "${agent_path}/${config_file}" ] || { err "Expected file: ${agent_path}/${config_file}"; exit 1; }
  fi
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
  local config_file="${AGENT_CONFIG_FILE:-$AGENT_CONFIG_FILE_DEFAULT}"
  local config_link="${AGENT_CONFIG_LINK:-$AGENT_CONFIG_LINK_DEFAULT}"
  local skills_dir="${AGENT_SKILLS_DIR:-$AGENT_SKILLS_DIR_DEFAULT}"
  local skills_link="${AGENT_SKILLS_LINK:-$AGENT_SKILLS_LINK_DEFAULT}"

  mkdir -p "$agent_dir"

  ensure_link "${agent_path}/${agent_file}" "${agent_dir}/${agent_link}"
  if [ -n "$config_file" ]; then
    ensure_link "${agent_path}/${config_file}" "${agent_dir}/${config_link}"
  fi
  if [ -n "$skills_dir" ]; then
    ensure_link "${agent_path}/${skills_dir}" "${agent_dir}/${skills_link}"
  fi

  log "Symlinks set:"
  log "  ${agent_dir}/${agent_link} -> ${agent_path}/${agent_file}"
  if [ -n "$config_file" ]; then
    log "  ${agent_dir}/${config_link} -> ${agent_path}/${config_file}"
  fi
  if [ -n "$skills_dir" ]; then
    log "  ${agent_dir}/${skills_link} -> ${agent_path}/${skills_dir}"
  fi
}

install_tips_link() {
  local repo_dir="$1"
  local agent_dir="${AGENT_DIR:-${CODEX_DIR:-$AGENT_DIR_DEFAULT}}"
  local tips_file="${TIPS_FILE:-$TIPS_FILE_DEFAULT}"
  local tips_link="${TIPS_LINK:-$TIPS_LINK_DEFAULT}"

  if [ -z "$tips_file" ] || [ -z "$tips_link" ]; then
    return 0
  fi

  local tips_path="$tips_file"
  if [ ! -f "$tips_path" ]; then
    tips_path="${repo_dir}/${tips_file}"
  fi
  [ -f "$tips_path" ] || { err "Expected tips file: ${tips_path}"; exit 1; }
  tips_path="$(cd "$(dirname "$tips_path")" && pwd -P)/$(basename "$tips_path")"

  mkdir -p "$agent_dir"
  ensure_link "$tips_path" "${agent_dir}/${tips_link}"

  log "Tips link set:"
  log "  ${agent_dir}/${tips_link} -> ${tips_path}"
}

install_tmux_conf() {
  local repo_dir="$1"
  local tmux_source="${TMUX_CONF_SOURCE:-$TMUX_CONF_SOURCE_DEFAULT}"
  local tmux_link="${TMUX_CONF_LINK:-$TMUX_CONF_LINK_DEFAULT}"

  if [ -z "$tmux_source" ] || [ -z "$tmux_link" ]; then
    return 0
  fi

  local tmux_path="$tmux_source"
  if [ ! -f "$tmux_path" ]; then
    tmux_path="${repo_dir}/${tmux_source}"
  fi
  [ -f "$tmux_path" ] || { err "Expected tmux conf: ${tmux_path}"; exit 1; }
  tmux_path="$(cd "$(dirname "$tmux_path")" && pwd -P)/$(basename "$tmux_path")"

  ensure_link "$tmux_path" "$tmux_link"

  log "tmux conf set:"
  log "  ${tmux_link} -> ${tmux_path}"
}

install_tm_helper() {
  local repo_dir="$1"
  local tm_link="${TM_LINK:-$TM_LINK_DEFAULT}"
  local bin_dir="${TM_BIN_DIR:-$TM_BIN_DIR_DEFAULT}"
  local tm_source="${TM_SOURCE:-$TM_SOURCE_DEFAULT}"

  if [ -z "$tm_link" ]; then
    return 0
  fi

  local tm_path="$tm_source"
  if [ ! -f "$tm_path" ]; then
    tm_path="${repo_dir}/${tm_source}"
  fi
  [ -f "$tm_path" ] || { err "Expected tm script: ${tm_path}"; exit 1; }
  tm_path="$(cd "$(dirname "$tm_path")" && pwd -P)/$(basename "$tm_path")"

  mkdir -p "$bin_dir"
  ensure_link "$tm_path" "${bin_dir}/${tm_link}"

  log "tm helper set:"
  log "  ${bin_dir}/${tm_link} -> ${tm_path}"
}

cron_expr_for_minutes() {
  local minutes="$1"
  if [ "$minutes" -lt 1 ]; then
    err "Invalid PULL_EVERY_MINUTES: ${minutes}"
    exit 1
  fi
  if [ "$minutes" -lt 60 ]; then
    printf '*/%s * * * *' "$minutes"
    return 0
  fi
  if [ $((minutes % 60)) -eq 0 ]; then
    printf '0 */%s * * *' "$((minutes / 60))"
    return 0
  fi
  err "PULL_EVERY_MINUTES over 59 must be divisible by 60; got ${minutes}, using 59"
  printf '*/59 * * * *'
}

detect_default_branch() {
  local repo_dir="$1"
  local branch=""
  branch="$(git -C "$repo_dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)"
  branch="${branch##*/}"
  if [ -z "$branch" ]; then
    branch="$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  fi
  printf '%s' "${branch:-$BRANCH_DEFAULT}"
}

install_cron_autopull() {
  local repo_dir="$1"
  local minutes="${PULL_EVERY_MINUTES:-$PULL_EVERY_MINUTES_DEFAULT}"
  local branch="${AGENT_CONFIG_BRANCH:-$(detect_default_branch "$repo_dir")}"
  local autopull_script="${repo_dir}/scripts/autopull.sh"
  local git_bin
  git_bin="$(command -v git)"
  local bash_bin
  bash_bin="$(command -v bash)"
  local cron_path="${AUTOPULL_PATH:-$PATH}"
  local log_path="${PULL_LOG_PATH-$PULL_LOG_PATH_DEFAULT}"
  local cron_expr
  cron_expr="$(cron_expr_for_minutes "$minutes")"

  # Pull only if:
  # - on the expected branch
  # - working tree is clean (prevents surprises while editing)
  local cron_line
  [ -f "$autopull_script" ] || { err "Expected autopull script: ${autopull_script}"; exit 1; }
  if [ -n "$log_path" ]; then
    cron_line="${cron_expr} PATH=\"${cron_path}\" GIT_BIN=\"${git_bin}\" PULL_LOG_PATH=\"${log_path}\" ${bash_bin} \"${autopull_script}\" \"${repo_dir}\" \"${branch}\" # ${CRON_TAG}"
  else
    cron_line="${cron_expr} PATH=\"${cron_path}\" GIT_BIN=\"${git_bin}\" ${bash_bin} \"${autopull_script}\" \"${repo_dir}\" \"${branch}\" # ${CRON_TAG}"
  fi

  local current
  current="$(crontab -l 2>/dev/null || true)"

  local filtered
  filtered="$(printf '%s\n' "$current" | grep -v "${CRON_TAG}" || true)"

  printf '%s\n%s\n' "$filtered" "$cron_line" | crontab -

  log "Cron installed/updated:"
  log "  ${cron_line}"
  if [ -n "$log_path" ]; then
    log "  Log file: ${log_path}"
  fi
  warn_if_cron_inactive
}

main() {
  need_cmd gh
  need_cmd git
  need_cmd bash
  need_cmd ln
  need_cmd crontab
  need_cmd grep
  need_cmd mv
  need_cmd date
  need_cmd readlink

  local repo_dir="${AGENT_CONFIG_REPO_DIR:-$REPO_DIR_DEFAULT}"

  # If running from the repo's scripts/, prefer that location.
  local script_root=""
  if script_root="$(script_repo_root)"; then
    repo_dir="$script_root"
    log "Detected repo root from script path: ${repo_dir}"
  fi

  # If running from inside a repo and no script root, prefer that location.
  local inside_root=""
  if [ -z "$script_root" ] && inside_root="$(repo_root_if_inside)"; then
    repo_dir="$inside_root"
    log "Detected repo root from current directory: ${repo_dir}"
  fi

  ensure_repo_present "$repo_dir"
  validate_layout "$repo_dir"
  install_symlinks "$repo_dir"
  install_tips_link "$repo_dir"
  install_tmux_conf "$repo_dir"
  install_tm_helper "$repo_dir"
  install_cron_autopull "$repo_dir"

  local dev_dir="${DEV_DIR:-$DEV_DIR_DEFAULT}"
  mkdir -p "$dev_dir"
  cd "$dev_dir"
  log "Now in ${dev_dir}"

  log "Done."
}

main "$@"
