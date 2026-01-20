# AGENTS.MD

Work style: telegraph; noun-phrases ok; drop grammar; min tokens.

## Agent Protocol
- Contact: Alex Kvamme (@kvamme (X), @apfk88 (Github)).
- “Make a note” => edit AGENTS.md (shortcut; not a blocker). Ignore `CLAUDE.md`.
- “Add a tip” => append to `tips.md` in agent-config repo and commit + push.
- Keep files <~500 LOC; split/refactor as needed.
- Prefer end-to-end verify; if blocked, say what’s missing.
- New deps: quick health check (recent releases/commits, adoption).
- Web: search early; quote exact errors; prefer 2025–2026 sources
- Use Codex background for long jobs

## Git
- IMPORTANT! Always save your changes in atomic commits: commit only the files you touched and list each path explicitly.
- For new projects, init git.
- Commit formatting: For tracked files run `git commit -m "<scoped message>" -- path/to/file1 path/to/file2`. For brand-new files, use the one-liner `git restore --staged :/ && git add "path/to/file1" "path/to/file2" && git commit -m "<scoped message>" -- path/to/file1 path/to/file2`
- Safe by default: `git status/diff/log`. Push only when user asks.
- Destructive ops forbidden unless explicit (`reset --hard`, `clean`, `restore`, `rm`, …).
- Don’t delete/rename unexpected stuff; stop + ask.
- No repo-wide S/R scripts; keep edits small/reviewable.
- Avoid manual `git stash`; if Git auto-stashes during pull/rebase, that’s fine (hint, not hard guardrail).
- If user types a command (“pull and push”), that’s consent for that command.
- Big review: `git --no-pager diff --color=never`.
- Multi-agent: check `git status/diff` before edits; ship small commits.
- PRs: use `gh pr view/diff` (no URLs).
- Commits: Conventional Commits (`feat|fix|refactor|build|ci|chore|docs|style|perf|test`).
- Publish repos as private by default unless explicitly specified otherwise

## Language/Stack Notes
- UV is used to manage python.
- Use repo’s package manager/runtime; no swaps w/o approval.
- Swift: use workspace helper/daemon; validate `swift build` + tests; keep concurrency attrs right.
- TypeScript: keep files small; follow existing patterns.
- Assume any web app will be deployed in Vercel
- Make sure the app builds (`npm build`) before pushing or deploying
- Use default Vercel stack when possible: Neon Postgres, Vercel Blob, Vercel Edge Config
- Use Clerk for auth

## Critical Thinking
- Fix root cause (not band-aid).
- Unsure: read more code; if still stuck, ask w/ short options.
- Conflicts: call out; pick safer path.
- Unrecognized changes: assume other agent; keep going; focus your changes. If it causes issues, stop + ask user.
- Leave breadcrumb notes in thread.

## UI
- Typography: pick a real font; avoid Inter/Roboto/Arial/system defaults.
- Theme: commit to a palette; use CSS vars; bold accents > timid gradients.
- Motion: 1–2 high-impact moments (staggered reveal beats random micro-anim).
- Background: add depth (gradients/patterns), not flat default.
- Avoid: purple-on-white clichés, generic component grids, predictable layouts.

## Docs/Readme/Agent.md
- Always keep readme up to date but focus on core instructins for other developers and agents
- Automatically keep the project Agent.md up to date with important information you don't want future agents not to know
- When relevant - if this is a user facing app that requires public docs - create docs when needed in `/docs/*`

## Tests
- I never think to write tests, so please write tests for core functionality as you go along.
- Bugs: add regression test when it fits.

## Browser Automation

Whenever you are working on a web application, proactively use `agent-browser` to inspect, test, and debug. Run `agent-browser --help` for all commands.

Core workflow:
1. `agent-browser open <url>` - Navigate to page
2. `agent-browser snapshot -i` - Get interactive elements with refs (@e1, @e2)
3. `agent-browser click @e1` / `fill @e2 "text"` - Interact using refs
4. Re-snapshot after page changes

Install:
1. `npm install -g agent-browser`
2. `agent-browser install`
3. Routinely update: `npm install -g agent-browser`
