#!/usr/bin/env bash
set -euo pipefail

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

repo_dir="$(git rev-parse --show-toplevel)"
home_dir="$tmp_dir/home"
bin_dir="$tmp_dir/bin"
mkdir -p "$home_dir/.codex" "$home_dir/.local/bin" "$bin_dir"

cat >"$bin_dir/gh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$bin_dir/gh"

cat >"$bin_dir/crontab" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "-l" ]; then
  exit 0
fi
cat >"${CRONTAB_CAPTURE}"
STUB
chmod +x "$bin_dir/crontab"

ln -s "${repo_dir}/tmux.conf" "$home_dir/.tmux.conf"
ln -s "${repo_dir}/scripts/tm" "$home_dir/.local/bin/tm"

CRONTAB_CAPTURE="$tmp_dir/crontab" \
HOME="$home_dir" \
PATH="$bin_dir:$PATH" \
PULL_LOG_PATH="" \
  bash "$repo_dir/scripts/bootstrap.sh"

for expected in \
  "$home_dir/.codex/agents.md" \
  "$home_dir/.codex/config.toml" \
  "$home_dir/.codex/skills" \
  "$home_dir/.codex/tips.md"
do
  if [ ! -L "$expected" ]; then
    echo "FAIL: expected link ${expected}" >&2
    exit 1
  fi
done

if [ -e "$home_dir/.tmux.conf" ] || [ -L "$home_dir/.tmux.conf" ]; then
  echo "FAIL: expected legacy tmux conf link removed" >&2
  exit 1
fi

if [ -e "$home_dir/.local/bin/tm" ] || [ -L "$home_dir/.local/bin/tm" ]; then
  echo "FAIL: expected legacy tm helper link removed" >&2
  exit 1
fi

if ! grep -q "agent-config-autopull" "$tmp_dir/crontab"; then
  echo "FAIL: expected autopull cron entry" >&2
  exit 1
fi

external_tmux_conf="$tmp_dir/external-tmux.conf"
external_tm="$tmp_dir/external-tm"
: >"$external_tmux_conf"
: >"$external_tm"
ln -s "$external_tmux_conf" "$home_dir/.tmux.conf"
ln -s "$external_tm" "$home_dir/.local/bin/tm"

CRONTAB_CAPTURE="$tmp_dir/crontab-second" \
HOME="$home_dir" \
PATH="$bin_dir:$PATH" \
PULL_LOG_PATH="" \
  bash "$repo_dir/scripts/bootstrap.sh"

if [ "$(readlink "$home_dir/.tmux.conf")" != "$external_tmux_conf" ]; then
  echo "FAIL: external tmux conf link should be left alone" >&2
  exit 1
fi

if [ "$(readlink "$home_dir/.local/bin/tm")" != "$external_tm" ]; then
  echo "FAIL: external tm helper link should be left alone" >&2
  exit 1
fi

printf '%s\n' "ok"
