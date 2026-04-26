# agent-config

Shared coding-agent config; symlink targets. Defaults to Codex today; add others (Claude, etc.) later.

## Layout
- `codex/` Codex config (AGENTS, rules, skills).
- `codex/skills/.system/` bundled system skills mirrored into this config repo.
- `codex/vercel.toml` Shared Vercel team/project IDs for quick CLI lookup/deploy flows.
- `scripts/bootstrap.sh` setup + auto-pull.
- `scripts/autopull.sh` cron runner (branch + clean-tree guard).

## Bootstrap
Prereqs: `gh` auth, `git`, `crontab`.

```sh
gh repo clone apfk88/agent-config ~/dev/agent-config
cd ~/dev/agent-config
chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh
```

Defaults (Codex):
- `~/.codex/agents.md` -> `codex/AGENTS.md`
- `~/.codex/config.toml` -> `codex/config.toml`
- `~/.codex/skills` -> `codex/skills`
- Spreadsheet, document, and presentation workflows come from OpenAI primary-runtime plugins, not local duplicate skills.
- `~/.codex/tips.md` -> `tips.md`
- cron: `scripts/autopull.sh` every 60m (expected branch + clean tree; logs to `~/.cache/agent-config/autopull.log`)
- legacy cleanup: removes old `~/.tmux.conf` and `~/.local/bin/tm` links only when they point into this repo.

Env overrides:
- `AGENT_CONFIG_REPO_DIR` (default `~/dev/agent-config`)
- `AGENT_CONFIG_REPO_SLUG` (default `apfk88/agent-config`)
- `AGENT_SUBDIR` (default `codex`)
- `AGENT_DIR` (default `~/.codex`)
- `AGENT_FILE` / `AGENT_LINK` (default `AGENTS.md` / `agents.md`)
- `AGENT_CONFIG_FILE` / `AGENT_CONFIG_LINK` (default `config.toml` / `config.toml`, set `AGENT_CONFIG_FILE=""` to skip)
- `AGENT_SKILLS_DIR` / `AGENT_SKILLS_LINK` (default `skills` / `skills`, set `AGENT_SKILLS_DIR=""` to skip)
- `TIPS_FILE` / `TIPS_LINK` (default `tips.md` / `tips.md`, set `TIPS_FILE=""` to skip)
- `LEGACY_TMUX_CONF_LINK` (default `~/.tmux.conf`, cleanup-only)
- `LEGACY_TM_BIN_DIR` / `LEGACY_TM_LINK` (default `~/.local/bin` / `tm`, cleanup-only)
- `AGENT_CONFIG_BRANCH` (default `main`)
- `PULL_EVERY_MINUTES` (default `60`)
- `PULL_LOG_PATH` (default `~/.cache/agent-config/autopull.log`, set empty to disable)
- `AUTOPULL_PATH` (defaults to current `PATH` at install time)

Other agents: set `AGENT_SUBDIR` + `AGENT_DIR` (and file/skills names if they differ).
Bootstrap is safe to re-run; it only backs up when links point elsewhere.
Tip: running `scripts/bootstrap.sh` by full path uses that repo (ignores current directory).

Disable auto-pull:
```sh
crontab -l | grep -v "agent-config-autopull" | crontab -
```

Linux note: ensure cron service is active (`cron` or `crond`), or auto-pull won't run.
