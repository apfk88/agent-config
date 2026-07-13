---
name: create-exe-project-vm
description: Provision and connect a project-specific exe.dev VM for remote Codex development. Use when asked to create, prepare, or reuse a proj-prefixed exe.dev project VM; tag it proj; attach restricted GitHub access; install personal agent-config; clone the project on both hosts; or connect the Codex desktop app to an exe.dev SSH project.
---

# Create exe.dev Project VM

Provision one durable VM per project. Use GitHub as the repository source of truth and Codex SSH connections for laptop-to-VM work.

## Defaults

- VM: `proj-<lowercase-kebab-slug>`
- exe.dev tag: `proj` (shown as `#proj`)
- GitHub owner: `apfk88`
- Laptop clone: `/Users/kvamme/dev/personal/<repo>`
- VM clone: `~/src/<repo>`
- Agent config clone: `~/repos/agent-config`
- GitHub access: two repo-scoped exe.dev integrations, one for the project and one for `apfk88/agent-config`
- Remote Codex config: `codex/config.exe.toml`; never link the macOS-specific `codex/config.toml` on Linux

## Guardrails

- Start with `git status --short --branch` in any local repository involved.
- Do not copy `~/.codex/auth.json`, GitHub tokens, SSH private keys, or other long-lived credentials to the VM.
- Use `codex login --device-auth` on the VM. The user completes the short-lived browser authorization.
- Keep GitHub access repo-scoped through exe.dev integrations. Do not run `gh auth login` on the VM.
- Do not rsync two working trees. Use Git or Codex Handoff.
- Do not silently commit existing local files. Inspect for secrets and obtain approval for an initial commit when files already exist.
- Reuse an existing exact-name VM only when its `proj` tag and repository mapping are compatible.
- Do not expose Codex app-server ports. The desktop app starts the remote server over SSH.

## 1. Resolve the repository

Normalize the requested project name to a lowercase kebab slug. Remove a leading `proj-` before constructing the VM name.

Inspect the requested local path or current repository:

1. Existing GitHub origin: reuse the local clone and derive `OWNER/REPO` from `origin`.
2. Existing local-only Git repository: default to private `apfk88/<repo>`. Create the GitHub remote and push existing commits. If uncommitted files must become the initial commit, show the proposed paths and obtain approval first.
3. No repository and target path absent: create a private GitHub repository with a README, cloning it under `/Users/kvamme/dev/personal`:

```bash
cd /Users/kvamme/dev/personal
gh repo create "apfk88/<repo>" --private --add-readme --clone
```

4. Non-empty, non-Git target path: inspect it before initializing Git. Never blanket-add possible secrets.

Confirm the local repository exists and its GitHub repository is accessible before provisioning.

## 2. Preview and provision

During skill development or when the user asks for a preview, run a no-write preview:

```bash
bash "${CODEX_HOME:-$HOME/.codex}/skills/create-exe-project-vm/scripts/provision_exe_project_vm.sh" \
  --dry-run \
  --repo "OWNER/REPO" \
  --local-path "/absolute/local/path" \
  "project slug"
```

For the real setup, omit `--dry-run`:

```bash
bash "${CODEX_HOME:-$HOME/.codex}/skills/create-exe-project-vm/scripts/provision_exe_project_vm.sh" \
  --repo "OWNER/REPO" \
  --local-path "/absolute/local/path" \
  "project slug"
```

The script:

1. Creates or reuses `proj-<slug>` and ensures tag `proj`.
2. Adds a concrete SSH alias to `~/.ssh/config`.
3. Attaches project and agent-config GitHub integrations.
4. Updates Codex on the VM.
5. Clones `agent-config`, runs its bootstrap, and links remote-safe config, instructions, skills, tips, and helpers.
6. Clones the project to `~/src/<repo>`.
7. Configures `GH_HOST`/`GH_REPO` for the restricted project integration.
8. Runs Codex device authentication unless already authenticated.
9. Verifies GitHub API access, Git access, Codex auth, app-server availability, and symlinks.

If exe.dev reports that GitHub is not linked, pause and ask the user to link the exe.dev GitHub App from the exe.dev Integrations page, then rerun. Do not fall back to a broad VM token.

## 3. Connect Codex desktop

After the script succeeds:

1. Open **Settings > Connections** in the Codex/ChatGPT desktop app.
2. Enable the concrete SSH host `proj-<slug>`.
3. Add remote project folder `/home/exedev/src/<repo>`.
4. Start a small remote task that runs `pwd` and `git status`.

Use supported app UI automation when available; otherwise give these three clicks to the user. For an existing local task, use the run-location control and **Hand off** after both project locations are saved.

## 4. Report

Return:

- VM name and SSH alias
- GitHub repository
- local and remote paths
- restricted integration host
- Codex authentication result
- remote verification result
- whether the desktop connection was added or still needs the UI step
