---
name: dot:homebrew-drift
description: Check the root Brewfile against what Homebrew has installed, for formulae and casks.
disable-model-invocation: true
---

# dot:homebrew-drift

Compare `Brewfile` in the repo root with the live Homebrew install. Two questions:

1. **Not in Brewfile:** is something installed (formulae you installed on request, and casks) that the Brewfile lacks?
2. **Not installed:** is something in the Brewfile that isn't installed?

## Ground rules

- Report only. Never edit the Brewfile, install, uninstall, or run `brew bundle` (including `cleanup`); the user does that.
- Scope is `brew` and `cask` lines. Taps, `mas`, `vscode` and outdated packages are out of scope.
- The repo is shared across machines: leave machine-specific installs (work tools, one-offs) out of the Brewfile.

## Steps

1. Run the comparison. It is read-only and prints the Brewfile it read, then two sections of `formula <name>` / `cask <name>` lines. Dependencies don't count as drift: a formula only shows under Not in Brewfile if it is a leaf you installed on request. Brewfile aliases (`kubectl` for `kubernetes-cli`) are resolved.

   ```bash
   bun .agents/skills/homebrew-drift/scripts/compare.js
   ```

2. Show one table per section: name, kind, suggestion, reason.
   - **Not in Brewfile:** suggest `add to Brewfile` (a tool or app the user plausibly wants on every machine) or `leave` (machine-specific, one-off, or a dependency). Look up unfamiliar names with `brew info` rather than guessing. Note `claude-code` vs `claude-code@latest`-style cases, where a different variant of a listed package is installed.
   - **Not installed:** suggest `brew bundle install` (never installed yet) or `remove from Brewfile` (obsolete, renamed, or replaced by an installed variant).

3. The user decides each row. Only on approval, edit the Brewfile (keep its existing ordering and quote style). Suggest the user runs `brew bundle`; don't run it. If you edited anything, run `bats tests/`, then rerun step 1.

## Known limits

Names match on the last path segment, so `arbourd/tap/go` and a core `go` count as the same package.

## Report

```
Not in Brewfile: <n>; recommend adding <list>, leaving <list>
Not installed:   <n>; recommend installing <list>, removing from Brewfile <list>
```
