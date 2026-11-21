# AGENTS.md

This repository automates a macOS environment. Symlink dotfiles into place. For configuration that an app rewrites, add a `dot merge` target.

## dot

Use `dot` as the single entry point. Keep it compatible with macOS zsh. For commands and targets, read `./dot help`.

For a new machine, follow Installation in `README.md`. Keep the order `init` → `link` → `install` → `merge`. Installation reads linked configuration, and merging needs installed tools and apps.

### Adding, renaming, or removing a command

Update all five locations in the same change:

1. `dot`: `_usage()` and the `case` statement
2. `README.md`: usage block in Installation
3. `.github/workflows/ci.yml`: `matrix.command` list
4. `tests/dot_test.nu`: the command's tests
5. `sh/completions/dot.fish`, `dot.bash`, and `_dot`: command lists and `-h`/`-v` flags

Completion requires agreement between `dot`, completions, and CI, enforced by tests. Manually make sure that the README usage block matches `./dot help` exactly.

### Adding, renaming, or removing a target

For an `install` or `merge` target, update these locations together:

1. `dot`: `_targets`, `_usage()`, and the `_install_<target>` function or `_merge_step` arm
2. All three files in `sh/completions/`: target lists
3. `README.md`: Installation usage block
4. For `install`, `.github/workflows/ci.yml`: `matrix.command`
5. `tests/dot_test.nu`: `dot-stubbed` function list and expected install/merge step sequences

Apply the same completion criteria as command changes.

Wrap every external command in an install step in `_spin`. It hides output behind a `gum` spinner unless the user passes `-v` or `--verbose`.

### Adding a dotfile

1. For agents, skills, or personas, edit `_link_agents`. For other dotfiles, edit `_link`.
2. If the target directory needs creation, add `_ensure`. Add `_symlink` for the target path.
3. For a new target directory, update `_clean_dir` in `_clean` and the `clean covers every directory it lists` test.
4. Add any new package to `Brewfile`.

## AI agents

Keep one symlink per persona and skill in `_link_agents`, so personal entries coexist with repository entries. The Antigravity `~/.gemini` paths come from Gemini CLI and remain unverified.

Put global instructions in `agents/AGENTS.md` and project instructions in each project's `AGENTS.md`.

Keep repository skills in `.agents/skills`, outside `dot` linking. `.claude/skills` points there and is force-added because the global gitignore excludes `.claude`.

### Agent configuration

For Claude configuration, record only chosen values and note each default. Keep hooks local: merge replaces arrays, so a repository `hooks` key replaces installed hooks for each named event.

Put Claude global keys such as `copyOnSelect` in `config.jsonc`, because Claude reads them only from `~/.claude.json`.

Merge Codex configuration with `yq`, with repository values taking precedence. Codex writes machine paths and trust hashes into the live file.

Pin plugin marketplaces with `ref`. For Renovate matching, keep `"repo"` before `"ref"` in JSON. In TOML, keep `source = "https://github.com/<owner>/<repo>.git"` before `ref`, including the `.git` suffix.

### Vendored skills

Change vendored skills upstream or through their pins in `agents/skills.json`. `agents/vendor-skills` overwrites `agents/skills/*` from each pinned `source` (`github.com/<owner>/<repo>/<path>@<commit>`).

Keep manual review for Renovate's grouped `vendored skills` PR. Preserve the `.github/workflows/skills.yml` guard: commit regenerated files only on Renovate's own same-repository `renovate/` PRs.

## Shell

Put primary shell configuration in `sh/config.fish` and bash/zsh fallback code in `sh/.shrc`. Keep shared fallback code POSIX. Guard shell-specific code with `$BASH_VERSION` or `$ZSH_VERSION`.

Keep private environment variables in `~/.config/fish/private.fish` and private Git configuration in `~/.config/git/private`. Keep both files untracked.

## Homebrew

Run the `Brewfile` bundle with `HOMEBREW_BUNDLE_NO_LOCK=1` to prevent a lockfile.

## Testing

After any change, run `tests/run`.

When adding tests, use `@test` commands in `tests/*_test.nu`. Limit names to letters, digits, spaces, and `, . : / - _`. The runner calls tests by bare name.

Keep each test's files in the scratch `home` passed from `@before-each` as `$in`. Tests run in parallel in separate `nu -n` processes. `@after-each` removes the scratch home even on failure.

After changing `.github/workflows`, run `actionlint`.

After changing `.github/renovate.json`, run this validator command on Node.

```bash
bunx --package renovate renovate-config-validator --strict
```
