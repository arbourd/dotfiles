# AGENTS.md

Automated macOS environment as code. Dotfiles are symlinked into place; nothing is copied.

## Entry point

`dot` (zsh) is the single entry point for all setup tasks:

| Command             | What it does                                                                    |
|---------------------|---------------------------------------------------------------------------------|
| `init`              | Clones this repo to `~/src/github.com/arbourd/dotfiles` and symlinks `dot` to `~/.local/bin/dot` |
| `update`            | Pulls latest changes and reports the version and whether it was updated         |
| `link`              | Symlinks all dotfiles into `~` and removes stale symlinks                       |
| `install`           | Runs brew + defaults + fisher + vim in order                                    |
| `install-brew`      | Installs/updates Homebrew packages from Brewfile                                |
| `install-defaults`  | Applies macOS `defaults write` settings                                         |
| `install-fisher`    | Installs/updates Fisher and fish plugins                                        |
| `install-vim`       | Installs/updates vim-plug and Vim plugins                                       |

On a new machine, run commands in this order: `init` → `link` → `install`. `link` must run before `install` because the install steps (fisher, vim) depend on config files already being in place at their expected locations.

## Repository layout

```
dot         # entry point — init/update/link/install subcommands
.macOS      # zsh script that applies macOS defaults write settings
Brewfile    # Homebrew formulae, casks, and Mac App Store apps
agents      # global AI agent persona and skill definitions
ghostty     # Ghostty terminal emulator config
git         # global git config, attributes, and gitignore
gpg         # GPG agent and key config
iterm       # iTerm 2 config (archived — do not modify or delete)
sh          # shell config: fish (primary), bash, and zsh fallback
vim         # vimrc and vim-plug plugin list
zed         # Zed editor settings and keybindings
tests       # zunit test suite for dotfiles
```

## AI Agents & Skills

AI configuration is managed via `agents/` and symlinked to tool-specific global paths.

- `agents/personas`: Persona or subagent definitions.
- `agents/skills`: Tool definitions and scripts.

Individual symlinks are used to allow personal, non-repo agents and skills to coexist in the target directories.

| Tool         | Skills                             | Personas / agents                |
| ------------ | ---------------------------------- | -------------------------------- |
| Claude Code  | `~/.claude/skills/<name>/SKILL.md` | `~/.claude/agents/*.md`          |
| Gemini CLI   | `~/.agents/skills/<name>/SKILL.md` | `~/.gemini/agents/*.md`          |
| OpenCode     | `~/.agents/skills/<name>/SKILL.md` | `~/.config/opencode/agents/*.md` |
| Pi           | `~/.agents/skills/<name>/SKILL.md` | `~/.pi/agent/prompts/*.md`       |
| Copilot      | `~/.agents/skills/<name>/SKILL.md` | `~/.copilot/agents/*.agent.md`   |

## Shell

Primary shell is **fish** (`/opt/homebrew/bin/fish`). `sh/.shrc` is a POSIX-compatible fallback used for bash and zsh. `dot` is zsh to maintain compatibility with macOS.

Private/sensitive env vars go in `~/.config/fish/private.fish` (not tracked; created empty by `_ensure`). Git private config goes in `~/.config/git/private` (not tracked; included via `git/config`).

## Homebrew

Packages are in `Brewfile`. Run with `HOMEBREW_BUNDLE_NO_LOCK=1` — no `Brewfile.lock.json` is generated or committed.

## Adding or removing a command

When a `dot` command is added, renamed, or removed, update all five of these in the same change:

1. `dot` — `_usage()` and the `case` statement
2. `README.md` — usage block in Installation
3. `AGENTS.md` — command table and repo layout comment
4. `.github/workflows/ci.yml` — `matrix.command` list
5. `tests/dot.zunit` — add or remove the corresponding test(s)

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs each `dot` command as a matrix job on `macos-latest`, plus a separate job that runs the zunit test suite on `ubuntu-latest`. MAS installs are skipped in CI via `HOMEBREW_BUNDLE_MAS_SKIP`. Dependabot keeps Actions up to date daily.

## Adding a new dotfile

1. Add the config file under an appropriately named directory.
2. Add an `_ensure` call for its target directory in `_link` if needed.
3. Add an `ln -vsf` line in `_link` pointing it to its target path.
4. If it requires a new package, add it to `Brewfile`.

## What not to change

- Do not add a `Brewfile.lock.json`; the bundle runs lock-free intentionally.
- Do not commit `~/.config/fish/private.fish` or `~/.config/git/private`; these are machine-local secrets.
- Do not skip GPG signing on commits (`--no-gpg-sign`).
