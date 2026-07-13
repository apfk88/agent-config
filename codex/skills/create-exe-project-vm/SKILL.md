---
name: create-exe-project-vm
description: Provision and connect a project-specific exe.dev VM for remote Codex development. Use when asked to create, prepare, or reuse a proj-prefixed exe.dev project VM; tag it proj; attach restricted GitHub access; install personal agent-config; clone the project on both hosts; or connect the Codex desktop app to an exe.dev SSH project.
---

# Create exe.dev Project VM

Provision one durable VM per project. Use GitHub as the repository source of truth and Codex SSH connections for laptop-to-VM work.

## Defaults

- VM: `proj-<lowercase-kebab-slug>`
- exe.dev tag: `proj` (shown as `#proj`)
- LLM attachment tag: `llm`
- GitHub owner: `apfk88`
- Laptop clone: `/Users/kvamme/dev/personal/<repo>`
- VM clone: `~/src/<repo>`
- Agent config clone: `~/repos/agent-config`
- GitHub access: two repo-scoped exe.dev integrations, one for the project and one for `apfk88/agent-config`
- Remote Codex config: `codex/config.exe.toml`; never link the macOS-specific `codex/config.toml` on Linux
- Remote branch: `codex/proj-<slug>` for automatic pushes without a `master` confirmation

## Guardrails

- Start with `git status --short --branch` in any local repository involved.
- Do not copy `~/.codex/auth.json`, GitHub tokens, SSH private keys, or other long-lived credentials to the VM.
- Use the exe.dev `llm` integration through `https://llm.int.exe.xyz/v1`; do not run per-VM Codex login.
- Use the local `#proj`-scoped SSH key for project VMs. Never disable 1Password SSH globally.
- Use the command-restricted exe.dev HTTPS token for provisioning. It must not permit VM deletion.
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

On the first run, bootstrap the local automation credentials. This requires one
1Password authorization, creates a no-passphrase key limited to `#proj` VMs,
mints a one-year control-plane token restricted to required non-delete
commands, and inserts a host-specific SSH block before `Host *`:

```bash
bash "${CODEX_HOME:-$HOME/.codex}/skills/create-exe-project-vm/scripts/bootstrap_exe_project_credentials.sh"
```

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
  --initial-prompt "THE USER'S FIRST BUILD REQUEST" \
  "project slug"
```

The script:

1. Creates or reuses `proj-<slug>` and ensures tags `proj` and `llm`.
2. Adds a concrete SSH alias to `~/.ssh/config`.
3. Attaches project and agent-config GitHub integrations.
4. Updates Codex on the VM.
5. Clones `agent-config`, runs its bootstrap, and links remote-safe config, instructions, skills, tips, and helpers.
6. Clones the project to `~/src/<repo>` and creates or reuses `codex/proj-<slug>`.
7. Configures `GH_HOST`/`GH_REPO` for the restricted project integration.
8. Runs `exeuntu configure codex` so the attached `llm` integration supplies the ChatGPT-backed provider without VM credentials, then layers the remote-safe personal defaults.
9. Creates the first task through the VM's Codex app-server with `approval: never` and `danger-full-access`, preserving the VM's working restricted GitHub network path. With no prompt, it seeds and immediately interrupts a readiness marker so the task appears without waiting on the model endpoint; with `--initial-prompt`, it runs that build request remotely.
10. Registers and auto-connects the SSH host and project through `~/.codex/codex-app/config.json` plus the app's `codex://codex-app/apply-config` deep link.
11. Verifies GitHub API access, Git access, a real Codex response, app-server availability, and symlinks.

If exe.dev reports that GitHub is not linked, pause and ask the user to link the exe.dev GitHub App from the exe.dev Integrations page, then rerun. Do not fall back to a broad VM token.

## 3. Verify Codex desktop and start remotely

After the script succeeds:

1. Use the Codex app project-list tool and find the project whose host is `remote-ssh-discovered:proj-<slug>` and whose path is `/home/exedev/src/<repo>`. Retry briefly while the deep link is being applied.
2. If it does not appear, inspect the desktop log and `~/.codex/codex-app/config.json`; do not ask the user to enable the connection manually.
3. Find the task ID returned as `remote_thread_id`. Do not create a replacement task through the desktop background-task API; its safety sandbox can block the restricted GitHub host.
4. Verify that task has the expected remote host and `cwd`; if an initial prompt ran, also inspect its branch report. Open it with the Codex navigation tool and include the created-task directive in the final response.

No Connections UI step is expected. For an existing *other* local task, use Codex Handoff after the matching remote project appears; a task cannot hand itself off.

## 4. Report

Return:

- VM name and SSH alias
- GitHub repository
- local and remote paths
- restricted integration host
- remote branch
- Codex provider verification result
- remote verification result
- desktop connection/project registration result
- created remote task
