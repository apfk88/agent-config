# agent-config

Shared coding-agent config; symlink targets. Defaults to Codex today; add others (Claude, etc.) later.

## Layout
- `codex/` Codex config (AGENTS, rules, skills).
- `scripts/bootstrap.sh` setup + auto-pull.
- `scripts/tm` tmux session helper.

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
- `~/.codex/tips.md` -> `tips.md`
- `~/.local/bin/tm` -> `scripts/tm`
- cron: `git pull --ff-only` every 60m (expected branch + clean tree)

Env overrides:
- `AGENT_CONFIG_REPO_DIR` (default `~/dev/agent-config`)
- `AGENT_CONFIG_REPO_SLUG` (default `apfk88/agent-config`)
- `AGENT_SUBDIR` (default `codex`)
- `AGENT_DIR` (default `~/.codex`)
- `AGENT_FILE` / `AGENT_LINK` (default `AGENTS.md` / `agents.md`)
- `AGENT_CONFIG_FILE` / `AGENT_CONFIG_LINK` (default `config.toml` / `config.toml`, set `AGENT_CONFIG_FILE=""` to skip)
- `AGENT_SKILLS_DIR` / `AGENT_SKILLS_LINK` (default `skills` / `skills`, set `AGENT_SKILLS_DIR=""` to skip)
- `TIPS_FILE` / `TIPS_LINK` (default `tips.md` / `tips.md`, set `TIPS_FILE=""` to skip)
- `TM_BIN_DIR` (default `~/.local/bin`)
- `TM_LINK` (default `tm`, set `TM_LINK=""` to skip)
- `TM_SOURCE` (default `scripts/tm`)
- `AGENT_CONFIG_BRANCH` (default `main`)
- `PULL_EVERY_MINUTES` (default `60`)

Other agents: set `AGENT_SUBDIR` + `AGENT_DIR` (and file/skills names if they differ).
Bootstrap is safe to re-run; it only backs up when links point elsewhere.

Disable auto-pull:
```sh
crontab -l | grep -v "agent-config-autopull" | crontab -
```

## Tmux helper
`tm new` creates a session named after the repo (windows: agent-0, agent-1, server, bash, tips). If not in a repo, it prompts for a path or GitHub URL (clones if needed).  
Branch shorthand: `tm new org/repo#branch` or `tm new /path/to/repo branch`.
`tm attach` lists sessions and asks which to attach.  
`tm list` / `tm kill` / `tm rename` for session management.  
Tips window opens `~/dev/agent-config/tips.md` if present (otherwise `./tips.md`).

Make it runnable anywhere:
```sh
mkdir -p ~/.local/bin
ln -s "$PWD/scripts/tm" ~/.local/bin/tm
```
Ensure `~/.local/bin` is on `PATH`.
