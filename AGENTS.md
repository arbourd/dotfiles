# AGENTS.md

Automated macOS environment as code. Dotfiles are symlinked into place; nothing is copied.

## Entry point

`dot` (zsh) is the single entry point for all setup tasks:

| Command             | What it does                                                          |
|---------------------|-----------------------------------------------------------------------|
| `help`              | Usage                                                                 |
| `init`              | Clones to `$GETPATH/github.com/arbourd/dotfiles`, symlinks `dot` into `~/.local/bin` |
| `link`              | Symlinks dotfiles into `~` and removes stale symlinks |
| `merge [target...]`   | Merges Claude, Codex, Orca and Rex settings into their live configs, or only the targets given, in order (`claude`, `codex`, `orca`, `rex`) |
| `install [target...]` | brew + defaults + fisher + vim, in order, or only the targets given (`brew`, `defaults`, `fisher`, `vim`) |
| `update`            | Pulls; prints short SHA (or old → new) as a GitHub link               |
| `version`           | Current commit SHA                                                    |

On a new machine, run commands in this order: `init` → `link` → `merge` → `install`. `link` must run before `install` because the install steps (fisher, vim) depend on config files already being in place at their expected locations.

`-h`/`--help` prints usage for the whole tool, a command or a target (`dot help install brew`). An unknown or empty target is rejected before any step runs.

Install steps hide noisy external commands behind a `gum` spinner via `_spin`. Pass `-v` or `--verbose` (anywhere on the line) to see full output. New install steps should wrap external commands in `_spin`.

## Repository layout

```
dot         # entry point — init/update/link/merge/install subcommands
.macOS      # zsh script that applies macOS defaults write settings
Brewfile    # Homebrew formulae, casks, and Mac App Store apps
.github     # CI and skills-vendoring workflows, Renovate config
.agents     # this repo's own skills (not linked by dot); .claude/skills symlinks here
agents      # global AI agent instructions, personas, and vendored skills (skills.json + vendor-skills)
ghostty     # Ghostty terminal emulator config
git         # global git config and gitignore
gpg         # GPG agent config
orca        # Orca CLI launcher and keybindings (symlinked), settings (merged into Orca's db)
rex         # Rex.app preferences script, run by merge
sh          # shell config: fish (primary), bash, and zsh fallback
ssh         # SSH client config
vim         # vimrc and vim-plug plugin list
zed         # Zed editor settings
tests       # bats test suite for dotfiles
```

## AI Agents & Skills

AI configuration is managed via `agents/` and symlinked to tool-specific global paths.

- `agents/AGENTS.md`: Shared global instructions, loaded by every tool on every project (e.g. "don't push without being asked"). Project-specific instructions still belong in that project's own `AGENTS.md`, not here.
- `agents/personas`: Persona or subagent definitions.
- `agents/skills`: Skill definitions and scripts. Vendored from upstream repos (see Vendored skills).
- `agents/claude`: Claude Code-only files, symlinked into `~/.claude/` (except merged `settings.jsonc`).
- `agents/codex/config.toml`: Codex plugin marketplaces and enabled plugins, merged into `~/.codex/config.toml` by `dot merge` via `yq` (repo wins) because Codex writes machine paths and trust hashes there.

`.agents/skills` holds skills for working on this repo only, separate from `agents/skills` (global, linked by `dot link`). `.claude/skills` is a symlink to it so Claude Code finds them; it is force-added because the global gitignore excludes `.claude`.

Individual symlinks are used to allow personal, non-repo agents and skills to coexist in the target directories.

| Tool        | Skills                             | Personas / agents                | Global instructions     |
| ----------- | ---------------------------------- | -------------------------------- | ----------------------- |
| Claude Code | `~/.claude/skills/<name>/SKILL.md` | `~/.claude/agents/*.md`          | `~/.claude/AGENTS.md`   |
| Antigravity | `~/.agents/skills/<name>/SKILL.md` | `~/.gemini/agents/*.md`          | `~/.gemini/GEMINI.md`   |
| OpenCode    | `~/.agents/skills/<name>/SKILL.md` | `~/.config/opencode/agents/*.md` | —                       |
| Pi          | `~/.agents/skills/<name>/SKILL.md` | `~/.pi/agent/prompts/*.md`       | `~/.pi/agent/AGENTS.md` |
| Codex       | —                                  | —                                | `~/.codex/AGENTS.md`    |

Antigravity paths are carried over from Gemini CLI and unverified.

Plugin marketplaces in `agents/claude/settings.jsonc` and `agents/codex/config.toml` are pinned with `ref`. Renovate's regexes need `"repo"` then `"ref"` (JSON), or `source = "https://github.com/<owner>/<repo>.git"` then `ref` (TOML); keep that key order and the `.git` suffix.

## Claude Code settings

`agents/claude/settings.jsonc` is merged into `~/.claude/settings.json` by `dot merge`, and holds only the settings we chose to set, each with its default noted. After a Claude Code upgrade, or to check for settings drift, run the `dot:claude-settings` skill. It has the merge, defaults, and comparison details.

## Orca

`orca/settings.jsonc` is merged into Orca's SQLite profile db by `dot merge`, and holds only non-default values. After every Orca upgrade (`brew upgrade --cask arbourd/tap/orca`), or to check for settings drift, run the `orca-settings` skill. It has the merge, defaults, and comparison details.

## Vendored skills

Every skill in `agents/skills/` is fetched from an upstream repo, never hand-written. `agents/skills.json` lists each skill's `source` (`github.com/<owner>/<repo>/<path>@<commit>`). Upstream wins: don't edit `agents/skills/*`; `agents/vendor-skills` overwrites them from the pinned commits.

- Renovate (two `custom.regex` managers in `.github/renovate.json`) bumps the pins in one `vendored skills` PR with no automerge; that PR is the review gate. An entry with a `version` tag tracks releases, one without tracks `main`; `source` always holds the immutable commit.
- `.github/workflows/skills.yml` runs `agents/vendor-skills` on any PR that touches `agents/skills.json`, `agents/vendor-skills` or the workflow, and on manual dispatch. Only on Renovate's own same-repo `renovate/` PRs (keep that guard) does it commit the regenerated files to the branch and then fail if anything still differs from upstream; on a dispatch it runs the failing check only.
- The `orca-cli` and `orchestration` upstream files are stubs that load a version-matched guide via `orca skills get`, so an Orca upgrade needs no skill update.
- To add a skill, add its unpinned `source` to `agents/skills.json` and run `agents/vendor-skills <name>`, which pins it.

## Shell

Primary shell is **fish** (`/opt/homebrew/bin/fish`). `sh/.shrc` is a POSIX-compatible fallback used for bash and zsh. `dot` is zsh to maintain compatibility with macOS.

Private/sensitive env vars go in `~/.config/fish/private.fish` (not tracked; created empty by `_ensure`). Git private config goes in `~/.config/git/private` (not tracked; included via `git/config`).

## Homebrew

Packages are in `Brewfile`. Run with `HOMEBREW_BUNDLE_NO_LOCK=1`; the bundle is lock-free intentionally, so never add a `Brewfile.lock.json`.

## Testing

Run the bats suites locally after any `dot` script change:

```bash
bats tests/
```

`tests/dot.bats` covers `dot` and the repo's config files. `tests/claude-settings.bats` covers the `dot:claude-settings` skill's `compare.js`, which is a repo-local script, not part of `dot`. The suites need `zsh`, `jq`, `yq`, `sqlite3`, `node`, and `script` (tty tests run under a pty via `_tty`). It also fails if the `dot` command list, `install`/`merge` targets, completions, and CI matrix drift apart, or if `agents/claude/settings.jsonc` gains a `hooks` key or its marketplace pins stop matching the Renovate regexes, or a vendored skill isn't pinned to a commit in `agents/skills.json`, or a Codex marketplace lacks a `.git` GitHub source or a non-empty `ref`.

Run `actionlint` after changing anything under `.github/workflows`.

Validate `.github/renovate.json` after changing it:

```bash
npx --yes --package renovate -- renovate-config-validator --strict
```

## Adding or removing a command

When a `dot` command is added, renamed, or removed, update all six of these in the same change:

1. `dot` — `_usage()` and the `case` statement
2. `README.md` — usage block in Installation
3. `AGENTS.md` — command table and repo layout comment
4. `.github/workflows/ci.yml` — `matrix.command` list
5. `tests/dot.bats` — add or remove the corresponding test(s); the command-sync test only checks `dot`, completions, and CI, so README and AGENTS.md drift silently
6. `sh/completions/` — `dot.fish`, `dot.bash`, and `_dot` command lists (and `-h`/`-v` flags)

When an `install` or `merge` target is added, renamed, or removed, update `_targets` and the `_install`/`_merge` case in `dot`, the target lists in `sh/completions/`, and (for `install`) the CI matrix; a bats test checks they agree.

## Adding a new dotfile

1. Add the config file under an appropriately named directory.
2. Add an `_ensure` call for its target directory in `_link` if needed.
3. Add a `_symlink` call in `_link` pointing it to its target path.
4. If the target directory is new, add it to the `_clean_dir` list in `_clean` and to the directory list in the `clean covers every directory it lists` test.
5. If it requires a new package, add it to `Brewfile`.

For agents, skills, or personas, edit `_link_agents` instead of `_link`.

## What not to change

- Do not add a `hooks` key to `agents/claude/settings.jsonc`; `_merge_claude_settings` replaces arrays
  wholesale, silently deleting any hooks installed locally in `~/.claude/settings.json`.
