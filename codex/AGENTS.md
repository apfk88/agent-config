# AGENTS.MD

Work style: telegraph; noun-phrases ok; drop grammar; min tokens.

## Agent Protocol
- Contact: Alex Kvamme (@kvamme (X), @apfk88 (Github)).
- “Make a note” => edit AGENTS.md (shortcut; not a blocker). Ignore `CLAUDE.md`.
- “Add a tip” => append to `tips.md` in agent-config repo and commit + push.
- Reasoning: default `xhigh`; lower only when explicitly optimizing for latency/cost.
- Keep files <~500 LOC; split/refactor as needed.
- Prefer end-to-end verify; if blocked, say what’s missing.
- New deps: quick health check (recent releases/commits, adoption).
- Web: use current primary sources; quote exact errors.
- Team Config: prefer repo `.codex/` (layered over `~/.codex`) for shared rules/skills/config
- Config debugging: start with `codex doctor --all`; use `/status`, `/permissions`, `codex features list`, and `codex debug prompt-input` as needed.
- Speed mode: Standard by default; use `/fast status|on|off` when supported.

## Git
- IMPORTANT! Always save your changes in atomic commits: commit only the files you touched and list each path explicitly.
- For new projects, init git.
- Commit formatting: For tracked files run `git commit -m "<scoped message>" -- path/to/file1 path/to/file2`. For brand-new files, use the one-liner `git restore --staged :/ && git add "path/to/file1" "path/to/file2" && git commit -m "<scoped message>" -- path/to/file1 path/to/file2`
- For app changes, run the project build before committing when a build command exists. If blocked, state what is missing.
- On non-`master` branches, push every commit (`git push`) unless the user explicitly asks for local-only commits.
- On `master`, ask once per session whether to push commits as they are created; follow that answer for the rest of the session without re-asking.
- Protected ops need explicit user request: `reset --hard`, `clean`, `restore`, `rm`, delete/rename unexpected files.
- No repo-wide S/R scripts; keep edits small/reviewable.
- Avoid manual `git stash`; if Git auto-stashes during pull/rebase, that’s fine (hint, not hard guardrail).
- If user types a command (“pull and push”), that’s consent for that command.
- Big review: `git --no-pager diff --color=never`.
- Multi-agent: check `git status/diff` before edits; ship small commits.
- PRs: use `gh pr view/diff` (no URLs).
- Commits: Conventional Commits (`feat|fix|refactor|build|ci|chore|docs|style|perf|test`).
- Publish repos as private by default unless explicitly specified otherwise
- Unrecognized changes: assume user/agent; don't revert; stop only if blocking.

## Language/Stack Notes
- UV is used to manage python.
- fnm is used to manage node
- Use repo’s package manager/runtime; no swaps w/o approval.
- Swift: follow existing project tooling; for Swift packages, validate `swift build` + tests; keep concurrency attrs right.
- For new web apps without existing stack conventions, deploy to Vercel.
- For those new Vercel apps, keep IDs in-repo at `codex/vercel.toml` (`team_id`, `project_id`, optional aliases).
- Prefer Neon Postgres, Vercel Blob, Vercel Edge Config, and Clerk for those new apps unless requirements point elsewhere.

## UI
- Typography: pick a real font; avoid Inter/Roboto/Arial/system defaults.
- Theme: commit to a palette; use CSS vars; bold accents > timid gradients.
- Motion: 1–2 high-impact moments (staggered reveal beats random micro-anim).
- Background: add depth (gradients/patterns), not flat default.
- Avoid: purple-on-white clichés, generic component grids, predictable layouts.

## Docs/README/AGENTS.md
- When implementation changes developer setup or public behavior, update the README or public docs as needed.
- Update project `AGENTS.md` only when recurring, project-specific guidance should persist.
- For user-facing apps that require public documentation, create or update `/docs/*` as needed.

## Tests
- I never think to write tests, so please write tests for core functionality as you go along.
- Bugs: add regression test when it fits.
