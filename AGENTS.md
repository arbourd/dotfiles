# AGENTS.md

This repository automates a macOS environment. Symlink dotfiles into place. For configuration that an app rewrites, add a `dot merge` target.

## dot

Use the Go binary built from `cmd/dot` as the entry point. Keep it compatible with macOS. For command behavior, read the cobra command definitions in `internal/cli`.

`dot init` makes a blobless sparse clone at `$XDG_DATA_HOME/dotfiles`, or `~/.local/share/dotfiles` when `XDG_DATA_HOME` is unset. `DOT_DIR` points dot at another checkout, such as a full development clone. `dot update` reapplies `repo.SparsePatterns` to sparse clones.

For a new machine, run `install.sh`: it installs the latest release binary and runs `dot init`. Keep the order `init` → `link` → `install` → `merge`. Installation reads linked configuration, and merging needs installed tools and apps. Releases come from `v*` tags through GoReleaser, configured in `.goreleaser.yaml` and `.github/workflows/release.yml`. Agents never push tags or publish releases.

### Commands and targets

The main command is in `cmd/dot`. `internal/cli` defines cobra commands; `targets.go` holds the install and merge targets table that drives help, completion, validation, and step order. A step is `func(ctx, *ui.UI) error`. Cobra generates completions with `dot completion fish|bash|zsh` from the targets table.

When adding or changing a target, update `internal/cli/targets.go` and its implementation in `internal/install` or `internal/merge`. Wrap external install commands with `ui.SpinCmd` or `ui.Spin`; output is shown directly with `-v` and otherwise handled by the spinner.

Install pins live in `internal/install/pins.go`, which Renovate updates. Keep each `// renovate:` comment directly above its const.

### Dotfiles and sparse clones

Add or change symlinks in the link tables in `internal/link`. For a new home directory, add it to `CleanDirs` or `CleanAgentDirs`. For a new top-level repo folder, add it to `repo.SparsePatterns`, the allowlist of paths checked out in the managed clone. `TestSparseCloneHasEveryRuntimePath` fails when a runtime path is missing from that allowlist.

Add new packages to `Brewfile`. Run its bundle with `HOMEBREW_BUNDLE_NO_LOCK=1` to prevent a lockfile.

The zsh `dot`, hand-written `sh/completions/*`, `tests/dot_test.nu`, and old zsh CI jobs are legacy files pending removal by the owner.

## AI agents

Keep one symlink per persona and skill in `internal/link`, so personal entries coexist with repository entries. The Antigravity `~/.gemini` paths come from Gemini CLI and remain unverified.

Put global instructions in `agents/AGENTS.md` and project instructions in each project's `AGENTS.md`.

Keep repository skills in `.agents/skills`, outside `dot` linking. `.claude/skills` points there and is force-added because the global gitignore excludes `.claude`.

### Agent configuration

For Claude configuration, record only chosen values and note each default. Keep hooks local: merge replaces arrays, so a repository `hooks` key replaces installed hooks for each named event.

Put Claude global keys such as `copyOnSelect` in `config.jsonc`, because Claude reads them only from `~/.claude.json`.

Codex configuration is merged in Go, with repository values taking precedence. Codex writes machine paths and trust hashes into the live file.

Pin plugin marketplaces with `ref`. For Renovate matching, keep `"repo"` before `"ref"` in JSON. In TOML, keep `source = "https://github.com/<owner>/<repo>.git"` before `ref`, including the `.git` suffix.

### Vendored skills

Change vendored skills upstream or through their pins in `agents/skills.json`. `agents/vendor-skills` overwrites `agents/skills/*` from each pinned `source` (`github.com/<owner>/<repo>/<path>@<commit>`).

A skill in `agents/skills/` without a `skills.json` entry is local. Edit it in place.

Keep manual review for Renovate's grouped `vendored skills` PR. Preserve the `.github/workflows/skills.yml` guard: commit regenerated files only on Renovate's own same-repository `renovate/` PRs.

## Shell

Put primary shell configuration in `sh/config.fish` and bash/zsh fallback code in `sh/.shrc`. Keep shared fallback code POSIX. Guard shell-specific code with `$BASH_VERSION` or `$ZSH_VERSION`.

Keep private environment variables in `~/.config/fish/private.fish` and private Git configuration in `~/.config/git/private`. Keep both files untracked.

## Testing

After any change, run `go test ./...` and `tests/run`. Go tests cover dot. The nu suites in `tests/` cover repository configuration and Renovate.

When adding nu tests, use `@test` commands in `tests/*_test.nu`. Limit names to letters, digits, spaces, and `, . : / - _`. The runner calls tests by bare name. Keep each test's files in the scratch `home` passed from `@before-each` as `$in`. Tests run in parallel in separate `nu -n` processes. `@after-each` removes the scratch home even on failure.

After changing `.github/workflows`, run `actionlint`.

After changing `.github/renovate.json`, run this validator command on Node:

```bash
bunx --package renovate renovate-config-validator --strict
```
