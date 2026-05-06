# AGENTS.md

Automated macOS environment as code. Dotfiles are symlinked into place; nothing is copied.

## Entry point

`dot.sh` (zsh) is the single entry point for all setup tasks:

| Command             | What it does                                      |
|---------------------|---------------------------------------------------|
| `clone`             | Clones this repo to `~/src/github.com/arbourd/dotfiles` |
| `link`              | Symlinks all dotfiles into `~`                    |
| `install`           | Runs brew + defaults + fisher + vim in order      |
| `install-brew`      | Installs/updates Homebrew packages from Brewfile  |
| `install-defaults`  | Applies macOS `defaults write` settings           |
| `install-fisher`    | Installs/updates Fisher and fish plugins          |
| `install-vim`       | Installs/updates vim-plug and Vim plugins         |

`_pre` (called before every install/link) creates required directories and the empty `~/.config/fish/private.fish` file.

On a new machine, run commands in this order: `clone` → `link` → `install`. `link` must run before `install` because the install steps (fisher, vim) depend on config files already being in place at their expected locations.

## Repository layout

```
dot.sh      # main script
Brewfile    # Homebrew packages, casks, and MAS apps
.macOS      # macOS defaults (zsh script)
ghostty     # ghostty config
git         # git config and global ignore
gpg         # gpg config
iterm       # iTerm 2 config (archived — do not modify or delete)
sh          # bash, fish, zsh config
vim         # vim config
```

## Shell

Primary shell is **fish** (`/opt/homebrew/bin/fish`). `sh/.shrc` is a POSIX-compatible fallback used for bash and zsh.

Key environment variables set in both:

- `EDITOR=vim`
- `GOPATH=$HOME/go` with `$GOPATH/bin` on PATH
- `$HOME/.cargo/bin` on PATH (Rust)
- `GPG_TTY=$(tty)`

Initializations (conditional on binary presence): Homebrew shellenv, zoxide.

Private/sensitive env vars go in `~/.config/fish/private.fish` (not tracked; created empty by `_pre`). Git private config goes in `~/.config/git/private` (not tracked; included via `git/config`).

## Homebrew

Packages are in `Brewfile`. Run with `HOMEBREW_BUNDLE_NO_LOCK=1` — no `Brewfile.lock.json` is generated or committed.

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs each `dot.sh` command as a matrix job on `macos-latest`. MAS installs are skipped in CI via `HOMEBREW_BUNDLE_MAS_SKIP`. Dependabot keeps Actions up to date daily.

## Adding a new dotfile

1. Add the config file under an appropriately named directory.
2. Add a `mkdir -p` for its target directory in `_pre` if needed.
3. Add an `ln -vsf` line in `_link` pointing it to its target path.
4. If it requires a new package, add it to `Brewfile`.

## What not to change

- Do not add a `Brewfile.lock.json`; the bundle runs lock-free intentionally.
- Do not commit `~/.config/fish/private.fish` or `~/.config/git/private`; these are machine-local secrets.
- Do not skip GPG signing on commits (`--no-gpg-sign`).
