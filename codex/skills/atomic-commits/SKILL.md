---
name: atomic-commits
description: Enforce atomic git commits by committing only the files touched and listing each path explicitly. Use when asked to create commits, split changes, or stage files so each commit is focused and limited to specific file paths.
---

# Atomic Commits

## Overview

Commit only the files touched for a single logical change. Always pass explicit paths to `git commit` and avoid blanket staging.

## Workflow

1. Inspect state: `git status -sb`, `git diff`, `git diff --staged`.
2. Define the smallest logical change (one commit scope).
3. Commit only the files in that scope with explicit paths.

## Commands

### Tracked files only

```
git commit -m "<scoped message>" -- path/to/file1 path/to/file2
```

### New files included

```
git restore --staged :/ && git add "path/to/file1" "path/to/file2" && git commit -m "<scoped message>" -- path/to/file1 path/to/file2
```

## Guardrails

- Never use `git commit -am` or `git add .` for atomic commits.
- Leave unrelated changes unstaged and uncommitted.
- If a single file mixes concerns, split by hunks before committing.
