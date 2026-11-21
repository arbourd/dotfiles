# AGENTS.md

Automated macOS environment as code. Dotfiles are symlinked into place, never copied; config an app rewrites itself is merged in by `dot merge` instead (a new `merge` target).

## dot

`dot` (zsh, for macOS compatibility) is the single entry point; `./dot help` lists its commands and `install`/`merge` targets. On a new machine run `init` → `link` → `install` → `merge`: install steps (fisher, vim) read config that `link` puts in place, and `merge` needs `yq` and the apps `install` provides.

### Adding, renaming, or removing a command

Update all five in the same change:

1. `dot`: `_usage()` and the `case` statement
2. `README.md`: usage block in Installation
3. `.github/workflows/ci.yml`: `matrix.command` list
4. `tests/dot_test.nu`: the command's test(s)
5. `sh/completions/`: `dot.fish`, `dot.bash`, and `_dot` command lists (and `-h`/`-v` flags)

A test checks `dot`, completions, and CI agree. Nothing checks README: its usage block must match `./dot help` output exactly.

For an `install` or `merge` target, update in the same change: `_targets`, `_usage()`, and an `_install_<target>` function (or a `_merge_step` arm) in `dot`; the target lists in `sh/completions/`; the README usage block; and, for `install`, the CI matrix. A test checks all but README.

Wrap every external command in an install step in `_spin`, which hides its output behind a `gum` spinner unless `-v`/`--verbose` is passed.

### Adding a dotfile

1. In `_link`, add an `_ensure` for its target directory if needed and a `_symlink` to its target path. For agents, skills, or personas, edit `_link_agents` instead.
2. For a new target directory, add it to the `_clean_dir` list in `_clean` and to the `clean covers every directory it lists` test.
3. Add any new package to `Brewfile`.

## AI agents

`agents/` is symlinked into each tool's global paths by `_link_agents`, one symlink per persona and skill so personal, non-repo agents and skills coexist in those directories. The `~/.gemini` paths (Antigravity) are carried over from Gemini CLI and unverified.

- `agents/AGENTS.md`: global instructions loaded by every tool on every project. Project-specific instructions belong in that project's own `AGENTS.md`.
- `agents/claude`: Claude Code-only files, symlinked into `~/.claude/`, except `settings.jsonc` and `config.jsonc`.
- `agents/claude/settings.jsonc`: merged into `~/.claude/settings.json` by `dot merge`. Holds only settings we chose, each with its default noted. Hooks stay local in `~/.claude/settings.json`: arrays replace wholesale on merge, so a repo `hooks` key would replace the installed hooks for every event it names.
- `agents/claude/config.jsonc`: merged into `~/.claude.json` by the same `dot merge claude`, with the same rules. Claude Code reads global-config keys (`copyOnSelect`) only from that file, never `settings.json`.
- `agents/codex/config.toml`: plugin marketplaces and enabled plugins, merged into `~/.codex/config.toml` by `dot merge` via `yq` (repo wins), since Codex writes machine paths and trust hashes there.

Plugin marketplaces in `settings.jsonc` and `codex/config.toml` are pinned with `ref`. Renovate's regexes (the `custom.regex` managers in `.github/renovate.json`) need `"repo"` then `"ref"` (JSON), or `source = "https://github.com/<owner>/<repo>.git"` then `ref` (TOML); keep that key order and the `.git` suffix.

`.agents/skills` holds skills for working on this repo, not linked by `dot`. `.claude/skills` symlinks to it and is force-added because the global gitignore excludes `.claude`.

### Vendored skills

Every skill in `agents/skills/` is fetched from upstream; upstream wins. `agents/skills.json` pins each `source` (`github.com/<owner>/<repo>/<path>@<commit>`), and `agents/vendor-skills` overwrites `agents/skills/*` from those pins, so change a skill upstream or via its pin.

- To add a skill, add its unpinned `source` to `agents/skills.json` (plus a `version` tag to track releases instead of `main`) and run `agents/vendor-skills <name>`, which pins it.
- Renovate bumps the pins in one `vendored skills` PR with no automerge; that PR is the review gate.
- `.github/workflows/skills.yml` commits regenerated files only on Renovate's own same-repo `renovate/` PRs; keep that guard.

## Shell

Shell config goes in `sh/config.fish` (fish is primary); `sh/.shrc` is the fallback for bash and zsh: shared code is POSIX, shell-specific code goes behind a `$BASH_VERSION`/`$ZSH_VERSION` guard.

Private env vars go in `~/.config/fish/private.fish`, private git config in `~/.config/git/private`; both are untracked.

## Homebrew

The `Brewfile` bundle is lock-free: run it with `HOMEBREW_BUNDLE_NO_LOCK=1`.

## Testing

After any change, run `nu tests/run.nu` (needs `nu`, `zsh`, `jq`, `yq`, `sqlite3`, `bun`, `script`).

A test is an `@test` command in a `tests/*_test.nu` file. `run.nu` calls each one by its bare name in its own `nu -n` process, so name tests with letters, digits, spaces and `, . : / - _`. Tests run in parallel: each gets a scratch `home` from `@before-each` as `$in`, removed by `@after-each` even on failure, so keep its files there.

After changing `.github/workflows`, run `actionlint`.

After changing `.github/renovate.json`, run the validator on Node (Renovate's native `re2` module crashes bun, so no `--bun`):

```bash
bunx --package renovate renovate-config-validator --strict
```
