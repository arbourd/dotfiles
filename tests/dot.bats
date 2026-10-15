#!/usr/bin/env bats

setup() {
    DOTFILES="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    FAKE_HOME="$(mktemp -d)"

    cat > "$FAKE_HOME/setup.zsh" <<SETUP
source '${DOTFILES}/dot'
_log() { :; }
unset GETPATH TERM_PROGRAM
HOME='${FAKE_HOME}'
DIR='${DOTFILES}'
SETUP
}

teardown() {
    rm -rf "$FAKE_HOME"
}

_perms() {
    if [[ "$(uname)" == "Darwin" ]]; then
        stat -f "%Sp" "$1"
    else
        stat -c "%A" "$1"
    fi
}

# _tty <command...> runs a command with stdout attached to a pty.
_tty() {
    command -v script > /dev/null || skip "script is not installed"
    if [[ "$(uname)" == "Darwin" ]]; then
        script -q /dev/null "$@"
    else
        script -qec "$(printf '%q ' "$@")" /dev/null
    fi
}

@test '_ensure leaves existing files untouched' {
    mkdir -p "$FAKE_HOME/cfg"
    echo secret > "$FAKE_HOME/cfg/private"
    zsh -c "source '$FAKE_HOME/setup.zsh'; _ensure '$FAKE_HOME/cfg/private'"
    [ "$(cat "$FAKE_HOME/cfg/private")" = "secret" ]
}

@test '_ensure creates directories, files, and permissions' {
    zsh -c "source '$FAKE_HOME/setup.zsh'; _ensure '$FAKE_HOME/test-dir/'"
    [ -d "$FAKE_HOME/test-dir" ]

    zsh -c "source '$FAKE_HOME/setup.zsh'; _ensure '$FAKE_HOME/test-parent/test-file'"
    [ -f "$FAKE_HOME/test-parent/test-file" ]

    zsh -c "source '$FAKE_HOME/setup.zsh'; _ensure '$FAKE_HOME/secret-dir/' 700"
    [ -d "$FAKE_HOME/secret-dir" ]
    [ "$(_perms "$FAKE_HOME/secret-dir")" = "drwx------" ]
}

@test '_require fails when command is missing' {
    run zsh -c "source '$FAKE_HOME/setup.zsh'; _require 'missing_cmd_$(date +%s)' 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Error:"* ]]
}

@test '_require succeeds when command exists' {
    run zsh -c "source '$FAKE_HOME/setup.zsh'; _require zsh"
    [ "$status" -eq 0 ]
}

@test 'init creates parent dirs, clones, and symlinks dot when target missing' {
    local target="$FAKE_HOME/src/github.com/arbourd/dotfiles"

    zsh -c "
        source '$FAKE_HOME/setup.zsh'
        GETPATH='$FAKE_HOME/src'
        git() { echo \"\$*\" > '$FAKE_HOME/git_args'; }
        _init
    "

    [ -d "$FAKE_HOME/src/github.com/arbourd" ]
    [ "$(cat "$FAKE_HOME/git_args")" = "clone https://github.com/arbourd/dotfiles.git $target" ]
    [ -L "$FAKE_HOME/.local/bin/dot" ]
    [ "$(readlink "$FAKE_HOME/.local/bin/dot")" = "$target/dot" ]
}

@test 'init pulls and re-symlinks dot when target already exists' {
    local target="$FAKE_HOME/src/github.com/arbourd/dotfiles"
    mkdir -p "$target"

    zsh -c "
        source '$FAKE_HOME/setup.zsh'
        GETPATH='$FAKE_HOME/src'
        git() { echo \"\$*\" > '$FAKE_HOME/git_args'; }
        _init
    "

    [ "$(cat "$FAKE_HOME/git_args")" = "-C $target pull" ]
    [ -L "$FAKE_HOME/.local/bin/dot" ]
    [ "$(readlink "$FAKE_HOME/.local/bin/dot")" = "$target/dot" ]
}

@test 'update reports up to date when HEAD does not change' {
    run zsh -c "
        source '$FAKE_HOME/setup.zsh'
        git() {
            if [[ \"\$*\" == *'rev-parse --short HEAD'* ]]; then echo 'abc1234'; return 0; fi
            if [[ \"\$*\" == *'pull --quiet'* ]]; then return 0; fi
            command git \"\$@\"
        }
        _update
    "

    [ "$status" -eq 0 ]
    [[ "$output" == *"pulling dotfiles"* ]]
    [[ "$output" == *"dotfiles abc1234 (up to date)"* ]]
}

@test 'update passes -v to git pull with --verbose' {
    run zsh -c "
        source '$FAKE_HOME/setup.zsh'
        VERBOSE=1
        git() {
            if [[ \"\$*\" == *'rev-parse --short HEAD'* ]]; then echo 'abc1234'; return 0; fi
            if [[ \"\$*\" == *'pull -v'* ]]; then echo pulled-verbose; return 0; fi
            echo \"unexpected git \$*\"; return 1
        }
        _update
    "

    [ "$status" -eq 0 ]
    [[ "$output" == *"pulled-verbose"* ]]
}

@test 'update links the compare url on a tty' {
    local flag="$FAKE_HOME/git_pull_flag"

    run _tty zsh -c "
        source '$FAKE_HOME/setup.zsh'
        flag='$flag'
        _spin() { shift; \"\$@\"; }
        git() {
            if [[ \"\$*\" == *'pull --quiet'* ]]; then touch \"\$flag\"; return 0; fi
            if [[ \"\$*\" == *'remote get-url origin'* ]]; then echo 'git@github.com:arbourd/dotfiles.git'; return 0; fi
            if [[ \"\$*\" == *'rev-parse --short HEAD'* ]]; then
                if [[ -e \"\$flag\" ]]; then echo 'def5678'; else echo 'abc1234'; fi
                return 0
            fi
            command git \"\$@\"
        }
        _update
    "

    [ "$status" -eq 0 ]
    [[ "$output" == *"https://github.com/arbourd/dotfiles/compare/abc1234...def5678"* ]]
    [[ "$output" == *"abc1234 → def5678"* ]]
    [[ "$output" == *"updated"* ]]
}

@test 'update reports old and new hashes when HEAD changes' {
    local flag="$FAKE_HOME/git_pull_flag"

    run zsh -c "
        source '$FAKE_HOME/setup.zsh'
        flag='$flag'
        git() {
            if [[ \"\$*\" == *'pull --quiet'* ]]; then touch \"\$flag\"; return 0; fi
            if [[ \"\$*\" == *'rev-parse --short HEAD'* ]]; then
                if [[ -e \"\$flag\" ]]; then echo 'def5678'; else echo 'abc1234'; fi
                return 0
            fi
            command git \"\$@\"
        }
        _update
    "

    [ "$status" -eq 0 ]
    [[ "$output" == *"updated"* ]]
    [[ "$output" == *"dotfiles abc1234 → def5678"* ]]
}

@test 'link creates dotfile symlinks' {
    zsh -c "source '$FAKE_HOME/setup.zsh'; _link" > /dev/null

    [ -L "$FAKE_HOME/.bash_profile" ]
    [ "$(readlink "$FAKE_HOME/.bash_profile")" = "$DOTFILES/sh/.shrc" ]
    [ -L "$FAKE_HOME/.bashrc" ]
    [ "$(readlink "$FAKE_HOME/.bashrc")" = "$DOTFILES/sh/.shrc" ]
    [ -L "$FAKE_HOME/.zshrc" ]
    [ "$(readlink "$FAKE_HOME/.zshrc")" = "$DOTFILES/sh/.shrc" ]
    [ -L "$FAKE_HOME/.config/fish/config.fish" ]
    [ "$(readlink "$FAKE_HOME/.config/fish/config.fish")" = "$DOTFILES/sh/config.fish" ]
    [ -L "$FAKE_HOME/.config/fish/fish_plugins" ]
    [ "$(readlink "$FAKE_HOME/.config/fish/fish_plugins")" = "$DOTFILES/sh/fish_plugins" ]
    [ -L "$FAKE_HOME/.config/fish/completions/dot.fish" ]
    [ "$(readlink "$FAKE_HOME/.config/fish/completions/dot.fish")" = "$DOTFILES/sh/completions/dot.fish" ]
    [ -L "$FAKE_HOME/.local/share/bash-completion/completions/dot" ]
    [ "$(readlink "$FAKE_HOME/.local/share/bash-completion/completions/dot")" = "$DOTFILES/sh/completions/dot.bash" ]
    [ -L "$FAKE_HOME/.zsh/completions/_dot" ]
    [ "$(readlink "$FAKE_HOME/.zsh/completions/_dot")" = "$DOTFILES/sh/completions/_dot" ]
    [ -L "$FAKE_HOME/.config/ghostty/config" ]
    [ "$(readlink "$FAKE_HOME/.config/ghostty/config")" = "$DOTFILES/ghostty/config" ]
    [ -L "$FAKE_HOME/.config/git/config" ]
    [ "$(readlink "$FAKE_HOME/.config/git/config")" = "$DOTFILES/git/config" ]
    [ -L "$FAKE_HOME/.config/git/gitignore" ]
    [ "$(readlink "$FAKE_HOME/.config/git/gitignore")" = "$DOTFILES/git/gitignore" ]
    [ -L "$FAKE_HOME/.gnupg/gpg-agent.conf" ]
    [ "$(readlink "$FAKE_HOME/.gnupg/gpg-agent.conf")" = "$DOTFILES/gpg/gpg-agent.conf" ]
    [ -L "$FAKE_HOME/.ssh/config" ]
    [ "$(readlink "$FAKE_HOME/.ssh/config")" = "$DOTFILES/ssh/config" ]
    [ -L "$FAKE_HOME/.vim/vimrc" ]
    [ "$(readlink "$FAKE_HOME/.vim/vimrc")" = "$DOTFILES/vim/vimrc" ]
    [ -L "$FAKE_HOME/.orca/keybindings.json" ]
    [ "$(readlink "$FAKE_HOME/.orca/keybindings.json")" = "$DOTFILES/orca/keybindings.json" ]
    [ -L "$FAKE_HOME/.config/zed/settings.json" ]
    [ "$(readlink "$FAKE_HOME/.config/zed/settings.json")" = "$DOTFILES/zed/settings.json" ]

    [ -d "$FAKE_HOME/.gnupg" ]
    [ "$(_perms "$FAKE_HOME/.gnupg")" = "drwx------" ]
    [ -f "$FAKE_HOME/.config/fish/private.fish" ]
    [ -f "$FAKE_HOME/.config/git/private" ]
}

@test 'link is idempotent and preserves private files' {
    zsh -c "source '$FAKE_HOME/setup.zsh'; _link" > /dev/null
    echo secret > "$FAKE_HOME/.config/fish/private.fish"
    echo secret > "$FAKE_HOME/.config/git/private"

    run zsh -c "source '$FAKE_HOME/setup.zsh'; _link"
    [ "$status" -eq 0 ]

    [ "$(readlink "$FAKE_HOME/.zshrc")" = "$DOTFILES/sh/.shrc" ]
    [ "$(readlink "$FAKE_HOME/.claude/AGENTS.md")" = "$DOTFILES/agents/AGENTS.md" ]
    [ "$(readlink "$FAKE_HOME/.claude/CLAUDE.md")" = "$DOTFILES/agents/claude/CLAUDE.md" ]
    [ "$(cat "$FAKE_HOME/.config/fish/private.fish")" = "secret" ]
    [ "$(cat "$FAKE_HOME/.config/git/private")" = "secret" ]
    [ ! -e "$FAKE_HOME/.claude/skills/skills" ]
}

@test 'link-agents creates agent symlinks with renaming' {
    mkdir -p "$FAKE_HOME/repo-mock/agents/claude" \
             "$FAKE_HOME/repo-mock/agents/personas" \
             "$FAKE_HOME/repo-mock/agents/skills/skill-a" \
             "$FAKE_HOME/repo-mock/agents/skills/skill-b"
    touch "$FAKE_HOME/repo-mock/agents/AGENTS.md" \
          "$FAKE_HOME/repo-mock/agents/claude/CLAUDE.md" \
          "$FAKE_HOME/repo-mock/agents/claude/statusline.sh" \
          "$FAKE_HOME/repo-mock/agents/personas/helper.md" \
          "$FAKE_HOME/repo-mock/agents/skills/skill-a/SKILL.md" \
          "$FAKE_HOME/repo-mock/agents/skills/skill-b/SKILL.md"
    echo '{}' > "$FAKE_HOME/repo-mock/agents/claude/settings.json"

    zsh -c "source '$FAKE_HOME/setup.zsh'; DIR='$FAKE_HOME/repo-mock'; _link_agents" > /dev/null

    [ -L "$FAKE_HOME/.claude/statusline.sh" ]
    [ "$(readlink "$FAKE_HOME/.claude/statusline.sh")" = "$FAKE_HOME/repo-mock/agents/claude/statusline.sh" ]
    [ -L "$FAKE_HOME/.claude/CLAUDE.md" ]
    [ "$(readlink "$FAKE_HOME/.claude/CLAUDE.md")" = "$FAKE_HOME/repo-mock/agents/claude/CLAUDE.md" ]

    [ -L "$FAKE_HOME/.claude/agents/helper.md" ]
    [ "$(readlink "$FAKE_HOME/.claude/agents/helper.md")" = "$FAKE_HOME/repo-mock/agents/personas/helper.md" ]
    [ -L "$FAKE_HOME/.gemini/agents/helper.md" ]
    [ "$(readlink "$FAKE_HOME/.gemini/agents/helper.md")" = "$FAKE_HOME/repo-mock/agents/personas/helper.md" ]
    [ -L "$FAKE_HOME/.pi/agent/prompts/helper.md" ]
    [ "$(readlink "$FAKE_HOME/.pi/agent/prompts/helper.md")" = "$FAKE_HOME/repo-mock/agents/personas/helper.md" ]
    [ -L "$FAKE_HOME/.config/opencode/agents/helper.md" ]
    [ "$(readlink "$FAKE_HOME/.config/opencode/agents/helper.md")" = "$FAKE_HOME/repo-mock/agents/personas/helper.md" ]

    [ -L "$FAKE_HOME/.claude/skills/skill-a" ]
    [ "$(readlink "$FAKE_HOME/.claude/skills/skill-a")" = "$FAKE_HOME/repo-mock/agents/skills/skill-a" ]
    [ -L "$FAKE_HOME/.agents/skills/skill-a" ]
    [ "$(readlink "$FAKE_HOME/.agents/skills/skill-a")" = "$FAKE_HOME/repo-mock/agents/skills/skill-a" ]
    [ -L "$FAKE_HOME/.claude/skills/skill-b" ]
    [ "$(readlink "$FAKE_HOME/.claude/skills/skill-b")" = "$FAKE_HOME/repo-mock/agents/skills/skill-b" ]
    [ -L "$FAKE_HOME/.agents/skills/skill-b" ]
    [ "$(readlink "$FAKE_HOME/.agents/skills/skill-b")" = "$FAKE_HOME/repo-mock/agents/skills/skill-b" ]

    [ -L "$FAKE_HOME/.claude/AGENTS.md" ]
    [ "$(readlink "$FAKE_HOME/.claude/AGENTS.md")" = "$FAKE_HOME/repo-mock/agents/AGENTS.md" ]
    [ -L "$FAKE_HOME/.gemini/GEMINI.md" ]
    [ "$(readlink "$FAKE_HOME/.gemini/GEMINI.md")" = "$FAKE_HOME/repo-mock/agents/AGENTS.md" ]
    [ -L "$FAKE_HOME/.codex/AGENTS.md" ]
    [ "$(readlink "$FAKE_HOME/.codex/AGENTS.md")" = "$FAKE_HOME/repo-mock/agents/AGENTS.md" ]
    [ -L "$FAKE_HOME/.pi/agent/AGENTS.md" ]
    [ "$(readlink "$FAKE_HOME/.pi/agent/AGENTS.md")" = "$FAKE_HOME/repo-mock/agents/AGENTS.md" ]
}

@test 'link-agents merges claude settings.json instead of symlinking it' {
    mkdir -p "$FAKE_HOME/repo-mock/agents/claude" "$FAKE_HOME/.claude"
    cat > "$FAKE_HOME/repo-mock/agents/claude/settings.json" <<'JSON'
{
  "theme": "dark",
  "editor": { "theme": "repo-theme" },
  "ignorePatterns": ["repo-pattern"]
}
JSON
    cat > "$FAKE_HOME/.claude/settings.json" <<'JSON'
{
  "hooks": { "SessionStart": [{ "matcher": "", "hooks": [] }] },
  "editor": { "theme": "live-theme", "fontSize": 14 },
  "ignorePatterns": ["live-pattern"]
}
JSON

    zsh -c "source '$FAKE_HOME/setup.zsh'; DIR='$FAKE_HOME/repo-mock'; _link_agents" > /dev/null

    [ ! -L "$FAKE_HOME/.claude/settings.json" ]
    [ -f "$FAKE_HOME/.claude/settings.json" ]

    run jq -r '.theme' "$FAKE_HOME/.claude/settings.json"
    [ "$output" = "dark" ]

    run jq -e '.hooks.SessionStart' "$FAKE_HOME/.claude/settings.json"
    [ "$status" -eq 0 ]

    # nested objects deep-merge with the repo winning on conflicting keys
    run jq -r '.editor.theme' "$FAKE_HOME/.claude/settings.json"
    [ "$output" = "repo-theme" ]
    run jq -r '.editor.fontSize' "$FAKE_HOME/.claude/settings.json"
    [ "$output" = "14" ]

    # arrays are replaced wholesale by the repo's, not unioned
    run jq -c '.ignorePatterns' "$FAKE_HOME/.claude/settings.json"
    [ "$output" = '["repo-pattern"]' ]
}

@test 'merge-claude-settings creates settings.json when none exists' {
    mkdir -p "$FAKE_HOME/repo-mock/agents/claude"
    echo '{"effortLevel": "high"}' > "$FAKE_HOME/repo-mock/agents/claude/settings.json"

    zsh -c "source '$FAKE_HOME/setup.zsh'; DIR='$FAKE_HOME/repo-mock'; _merge_claude_settings" > /dev/null

    run jq -r '.effortLevel' "$FAKE_HOME/.claude/settings.json"
    [ "$output" = "high" ]
}

@test 'merge-claude-settings handles an empty settings.json and sets 0600' {
    mkdir -p "$FAKE_HOME/repo-mock/agents/claude" "$FAKE_HOME/.claude"
    echo '{"effortLevel": "high"}' > "$FAKE_HOME/repo-mock/agents/claude/settings.json"
    : > "$FAKE_HOME/.claude/settings.json"
    chmod 644 "$FAKE_HOME/.claude/settings.json"

    zsh -c "source '$FAKE_HOME/setup.zsh'; DIR='$FAKE_HOME/repo-mock'; _merge_claude_settings" > /dev/null

    run jq -r '.effortLevel' "$FAKE_HOME/.claude/settings.json"
    [ "$output" = "high" ]
    [ "$(_perms "$FAKE_HOME/.claude/settings.json")" = "-rw-------" ]
}

@test 'repo claude settings.json has no hooks key' {
    run jq -e 'has("hooks") | not' "$DOTFILES/agents/claude/settings.json"
    [ "$status" -eq 0 ]
}

@test '_remove_stale_link guards and removal' {
    touch "$FAKE_HOME/real-file"
    zsh -c "source '$FAKE_HOME/setup.zsh'; _remove_stale_link '$FAKE_HOME/real-file' '$DOTFILES/'"
    [ -f "$FAKE_HOME/real-file" ]

    ln -sf "$DOTFILES/sh/.shrc" "$FAKE_HOME/live-link"
    zsh -c "source '$FAKE_HOME/setup.zsh'; _remove_stale_link '$FAKE_HOME/live-link' '$DOTFILES/'"
    [ -L "$FAKE_HOME/live-link" ]

    ln -sf "/etc/hosts" "$FAKE_HOME/external-link"
    zsh -c "source '$FAKE_HOME/setup.zsh'; _remove_stale_link '$FAKE_HOME/external-link' '$DOTFILES/'"
    [ -L "$FAKE_HOME/external-link" ]

    ln -sf "/nonexistent-outside-prefix" "$FAKE_HOME/dangling-external"
    zsh -c "source '$FAKE_HOME/setup.zsh'; _remove_stale_link '$FAKE_HOME/dangling-external' '$DOTFILES/'"
    [ -L "$FAKE_HOME/dangling-external" ]

    ln -sf "$DOTFILES/nonexistent" "$FAKE_HOME/stale-link"
    zsh -c "source '$FAKE_HOME/setup.zsh'; _remove_stale_link '$FAKE_HOME/stale-link' '$DOTFILES/'"
    [ -z "$(readlink "$FAKE_HOME/stale-link" 2>/dev/null)" ]
}

@test '_clean_dir reports removed links and none found' {
    mkdir "$FAKE_HOME/d"
    run zsh -c "source '$FAKE_HOME/setup.zsh'; _clean_dir '$DOTFILES/' '$FAKE_HOME/d'"
    [[ "$output" == *"none found"* ]]

    ln -sf "$DOTFILES/nonexistent" "$FAKE_HOME/d/stale"
    run zsh -c "source '$FAKE_HOME/setup.zsh'; _clean_dir '$DOTFILES/' '$FAKE_HOME/d'"
    [[ "$output" == *"removed"* ]]
    [[ "$output" != *"none found"* ]]
    [ ! -L "$FAKE_HOME/d/stale" ]
}

@test 'clean covers every directory it lists' {
    local d
    local -a dotdirs=("$FAKE_HOME" .config/fish .config/fish/completions .config/ghostty .config/git .config/zed .gnupg .local/share/bash-completion/completions .orca .ssh .vim .zsh/completions)
    local -a agentdirs=(.claude .claude/skills .agents/skills .claude/agents .gemini .gemini/agents .config/opencode/agents .pi/agent .pi/agent/prompts .codex)

    for d in "${dotdirs[@]}"; do
        [[ "$d" == "$FAKE_HOME" ]] || d="$FAKE_HOME/$d"
        mkdir -p "$d"
        ln -sf "$DOTFILES/nonexistent" "$d/stale"
        ln -sf "/nonexistent-outside-prefix" "$d/dangling-external"
    done
    for d in "${agentdirs[@]}"; do
        d="$FAKE_HOME/$d"
        mkdir -p "$d"
        ln -sf "$DOTFILES/agents/nonexistent" "$d/stale"
        ln -sf "/nonexistent-outside-prefix" "$d/dangling-external"
    done

    run zsh -c "source '$FAKE_HOME/setup.zsh'; _clean"
    [ "$status" -eq 0 ]
    [[ "$output" == *"removed"* ]]

    for d in "${dotdirs[@]}"; do
        [[ "$d" == "$FAKE_HOME" ]] || d="$FAKE_HOME/$d"
        [ ! -L "$d/stale" ]
        [ -L "$d/dangling-external" ]
    done
    for d in "${agentdirs[@]}"; do
        d="$FAKE_HOME/$d"
        [ ! -L "$d/stale" ]
        [ -L "$d/dangling-external" ]
    done
}

@test 'clean protects real files and unrelated symlinks' {
    zsh -c "source '$FAKE_HOME/setup.zsh'; _link" > /dev/null

    touch "$FAKE_HOME/.ssh/id_rsa"
    ln -sf /etc/hosts "$FAKE_HOME/.ssh/external_link"
    ln -sf "$DOTFILES/nonexistent" "$FAKE_HOME/.ssh/stale_link"

    zsh -c "source '$FAKE_HOME/setup.zsh'; _clean" > /dev/null

    [ -f "$FAKE_HOME/.ssh/id_rsa" ]
    [ -L "$FAKE_HOME/.ssh/external_link" ]
    [ "$(readlink "$FAKE_HOME/.ssh/external_link")" = "/etc/hosts" ]
    [ -z "$(readlink "$FAKE_HOME/.ssh/stale_link" 2>/dev/null)" ]
}

@test 'clean removes stale agent symlinks' {
    zsh -c "source '$FAKE_HOME/setup.zsh'; _link_agents" > /dev/null

    ln -sf "$DOTFILES/agents/skills/nonexistent" "$FAKE_HOME/.claude/skills/stale-skill"
    ln -sf /etc/hosts "$FAKE_HOME/.claude/skills/external-skill"
    ln -sf "$DOTFILES/agents/claude/nonexistent" "$FAKE_HOME/.claude/stale-claude-file"

    zsh -c "source '$FAKE_HOME/setup.zsh'; _clean" > /dev/null

    [ -z "$(readlink "$FAKE_HOME/.claude/skills/stale-skill" 2>/dev/null)" ]
    [ -L "$FAKE_HOME/.claude/skills/external-skill" ]
    [ -z "$(readlink "$FAKE_HOME/.claude/stale-claude-file" 2>/dev/null)" ]
}

@test 'handling paths with spaces' {
    local space_repo="$FAKE_HOME/path with spaces"
    mkdir -p "$space_repo/sh" "$space_repo/agents/claude"
    touch "$space_repo/sh/.shrc"
    echo '{}' > "$space_repo/agents/claude/settings.json"

    zsh -c "source '$FAKE_HOME/setup.zsh'; DIR='$space_repo'; _link" > /dev/null

    [ -L "$FAKE_HOME/.bash_profile" ]
    [ "$(readlink "$FAKE_HOME/.bash_profile")" = "$space_repo/sh/.shrc" ]
}

@test 'getpath resolution priority' {
    run zsh -c "
        set -e
        source '$FAKE_HOME/setup.zsh'
        git() {
            if [[ \"\$*\" == 'config --global get.path' ]]; then echo '/from/git/config'; return 0; fi
            command git \"\$@\"
        }
        [[ \"\$(_resolve_getpath)\" == '/from/git/config' ]]
        GETPATH='~/from/env'
        [[ \"\$(_resolve_getpath)\" == '~/from/env' ]]
        unset GETPATH
        git() { return 1; }
        [[ \"\$(_resolve_getpath)\" == '~/src' ]]
    "
    [ "$status" -eq 0 ]
}

@test 'init symlink target is absolute when getpath contains a literal tilde' {
    local target="$FAKE_HOME/src/github.com/arbourd/dotfiles"

    zsh -c "
        source '$FAKE_HOME/setup.zsh'
        GETPATH='~/src'
        git() { :; }
        _init
    "

    [ -L "$FAKE_HOME/.local/bin/dot" ]
    [ "$(readlink "$FAKE_HOME/.local/bin/dot")" = "$target/dot" ]
}

@test 'dot help prints usage and exits 0' {
    run zsh -c "cd '$DOTFILES' && ./dot help"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: dot [-v|--verbose] [COMMAND]"* ]]
}

@test 'dot version prints sha and exits 0' {
    local expected
    expected="$(git -C "$DOTFILES" rev-parse --short HEAD)"
    run zsh -c "cd '$DOTFILES' && ./dot version"
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
}

@test 'dot with no arguments exits 1 with error and usage on stderr' {
    run zsh -c "cd '$DOTFILES' && ./dot 2>&1 >/dev/null"
    [ "$status" -eq 1 ]
    [[ "$output" == *"error: command required"* ]]
    [[ "$output" == *"Usage: dot [-v|--verbose] [COMMAND]"* ]]
}

@test 'dot with unknown command exits 1 with error and usage on stderr' {
    run zsh -c "cd '$DOTFILES' && ./dot unknown 2>&1 >/dev/null"
    [ "$status" -eq 1 ]
    [[ "$output" == *'error: unknown command: "unknown"'* ]]
    [[ "$output" == *"Usage: dot [-v|--verbose] [COMMAND]"* ]]
}

# _orca_db creates a minimal Orca db and stubs pgrep so Orca looks closed.
_orca_db() {
    ORCA_DB="$FAKE_HOME/Library/Application Support/orca/profiles/local-default/profile-state.db"
    mkdir -p "${ORCA_DB%/*}"
    sqlite3 "$ORCA_DB" "CREATE TABLE profile_state_documents (domain TEXT PRIMARY KEY, payload TEXT, content_hash TEXT);
        INSERT INTO profile_state_documents VALUES ('settings', '{\"terminalScopeHistoryByWorktree\":true,\"other\":1}', 'stale');"

    mkdir -p "$FAKE_HOME/bin"
    printf '#!/bin/sh\nexit 1\n' > "$FAKE_HOME/bin/pgrep"
    chmod +x "$FAKE_HOME/bin/pgrep"
}

@test '_merge_orca_settings applies values and updates content_hash' {
    _orca_db

    zsh -c "source '$FAKE_HOME/setup.zsh'; PATH='$FAKE_HOME/bin':\$PATH; _merge_orca_settings" > /dev/null

    [ "$(sqlite3 "$ORCA_DB" "SELECT json_extract(payload, '\$.terminalScopeHistoryByWorktree') FROM profile_state_documents WHERE domain='settings'")" = "0" ]
    [ "$(sqlite3 "$ORCA_DB" "SELECT json_extract(payload, '\$.other') FROM profile_state_documents WHERE domain='settings'")" = "1" ]

    local payload hash
    payload=$(sqlite3 "$ORCA_DB" "SELECT payload FROM profile_state_documents WHERE domain='settings'")
    hash=$(sqlite3 "$ORCA_DB" "SELECT content_hash FROM profile_state_documents WHERE domain='settings'")
    [ "$(printf '%s' "$payload" | shasum -a 256 | cut -d' ' -f1)" = "$hash" ]
}

@test '_merge_orca_settings skips when Orca is running' {
    _orca_db
    printf '#!/bin/sh\nexit 0\n' > "$FAKE_HOME/bin/pgrep"

    run zsh -c "source '$FAKE_HOME/setup.zsh'; PATH='$FAKE_HOME/bin':\$PATH; _merge_orca_settings"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipped"* ]]
    [ "$(sqlite3 "$ORCA_DB" "SELECT content_hash FROM profile_state_documents WHERE domain='settings'")" = "stale" ]
}

@test '_merge_orca_settings skips when run inside Orca' {
    _orca_db

    run zsh -c "source '$FAKE_HOME/setup.zsh'; PATH='$FAKE_HOME/bin':\$PATH; TERM_PROGRAM=Orca; _merge_orca_settings"
    [ "$status" -eq 0 ]
    [[ "$output" == *"outside Orca"* ]]
    [ "$(sqlite3 "$ORCA_DB" "SELECT content_hash FROM profile_state_documents WHERE domain='settings'")" = "stale" ]
}

@test '_merge_orca_settings skips when db is missing' {
    run zsh -c "source '$FAKE_HOME/setup.zsh'; _merge_orca_settings"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipped"* ]]
    [ ! -e "$FAKE_HOME/Library" ]
}

@test '_merge_orca_settings fails when sqlite3 is missing' {
    _orca_db

    run zsh -c "source '$FAKE_HOME/setup.zsh'; PATH='$FAKE_HOME/bin'; _merge_orca_settings 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'sqlite3' is required"* ]]
}

@test '_status prints plain kind and detail when not a tty' {
    run zsh -c "source '$FAKE_HOME/setup.zsh'; _status merged 'a -> b'"
    [ "$status" -eq 0 ]
    [ "$output" = "merged   a -> b" ]
}

@test '_status shortens home and dotfiles paths' {
    run zsh -c "source '$FAKE_HOME/setup.zsh'; _status linked '$FAKE_HOME/.zshrc → $DOTFILES/sh/.shrc'"
    [ "$output" = "linked   ~/.zshrc → sh/.shrc" ]
}

@test '_err writes plain message to stderr when not a tty' {
    run zsh -c "source '$FAKE_HOME/setup.zsh'; _err boom 2>&1 >/dev/null"
    [ "$output" = "boom" ]
}

@test 'gum is used on a tty' {
    mkdir "$FAKE_HOME/bin"
    printf '#!/bin/sh\necho gum-was-called\n' > "$FAKE_HOME/bin/gum"
    chmod +x "$FAKE_HOME/bin/gum"

    run _tty zsh -c "source '$FAKE_HOME/setup.zsh'; PATH='$FAKE_HOME/bin':\$PATH; _spin title true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"gum-was-called"* ]]
}

@test '_spin propagates gum failure' {
    mkdir "$FAKE_HOME/bin"
    printf '#!/bin/sh\nexit 1\n' > "$FAKE_HOME/bin/gum"
    chmod +x "$FAKE_HOME/bin/gum"

    run _tty zsh -c "source '$FAKE_HOME/setup.zsh'; PATH='$FAKE_HOME/bin':\$PATH; _spin title false"
    [ "$status" -ne 0 ]
    [[ "$output" != *"ok "*"title"* ]]
}

@test 'NO_COLOR disables styling even on a tty with gum installed' {
    mkdir "$FAKE_HOME/bin"
    printf '#!/bin/sh\necho gum-was-called\n' > "$FAKE_HOME/bin/gum"
    chmod +x "$FAKE_HOME/bin/gum"

    run _tty zsh -c "source '$FAKE_HOME/setup.zsh'; PATH='$FAKE_HOME/bin':\$PATH; NO_COLOR=1; _spin title true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok       title"* ]]
    [[ "$output" != *"gum-was-called"* ]]
    [[ "$output" != *$'\e['* ]]
}

@test '_spin falls back to running the command without gum' {
    run zsh -c "source '$FAKE_HOME/setup.zsh'; _spin title echo ran"
    [ "$status" -eq 0 ]
    [[ "$output" == *"title"* ]]
    [[ "$output" == *"ran"* ]]
}

@test '_spin propagates command failure' {
    run zsh -c "source '$FAKE_HOME/setup.zsh'; _spin title false"
    [ "$status" -ne 0 ]
}

@test '_spin bypasses gum with --verbose' {
    mkdir "$FAKE_HOME/bin"
    printf '#!/bin/sh\necho gum-was-called\n' > "$FAKE_HOME/bin/gum"
    chmod +x "$FAKE_HOME/bin/gum"

    run zsh -c "source '$FAKE_HOME/setup.zsh'; PATH='$FAKE_HOME/bin':\$PATH; _has_gum() { true; }; VERBOSE=1; _spin title echo ran"
    [[ "$output" == *"ran"* ]]
    [[ "$output" != *"gum-was-called"* ]]
}

@test 'dot accepts -v and --verbose before or after the command' {
    for args in "-v version" "version -v" "--verbose version" "version --verbose"; do
        run zsh -c "cd '$DOTFILES' && ./dot $args"
        [ "$status" -eq 0 ]
        [ "$output" = "$(git -C "$DOTFILES" rev-parse --short HEAD)" ]
    done
}

@test '_symlink creates the link and reports it' {
    run zsh -c "source '$FAKE_HOME/setup.zsh'; _symlink '$DOTFILES/sh/.shrc' '$FAKE_HOME/.zshrc'"
    [ "$status" -eq 0 ]
    [ "$(readlink "$FAKE_HOME/.zshrc")" = "$DOTFILES/sh/.shrc" ]
    [ "$output" = "linked   ~/.zshrc → sh/.shrc" ]
}

@test '_symlink reports the link inside an existing directory target' {
    mkdir "$FAKE_HOME/skills"
    run zsh -c "source '$FAKE_HOME/setup.zsh'; _symlink '$DOTFILES/agents/skills' '$FAKE_HOME/skills'"
    [ -L "$FAKE_HOME/skills/skills" ]
    [[ "$output" == *"~/skills/skills"* ]]
}

@test 'install-fisher restores fish_plugins from the dotfiles repo, not the cwd' {
    local repo="$FAKE_HOME/repo"
    mkdir "$FAKE_HOME/bin" "$FAKE_HOME/cwd"
    mkdir -p "$repo/sh"
    echo original > "$repo/sh/fish_plugins"
    git init -q "$repo"
    git -C "$repo" add sh/fish_plugins
    git -C "$repo" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m init
    echo modified > "$repo/sh/fish_plugins"

    for cmd in brew curl; do
        printf '#!/bin/sh\n' > "$FAKE_HOME/bin/$cmd"
    done
    printf '#!/bin/sh\necho "$2" >> "%s/fish_args"\n' "$FAKE_HOME" > "$FAKE_HOME/bin/fish"
    chmod +x "$FAKE_HOME/bin/"*

    run zsh -c "source '$FAKE_HOME/setup.zsh'; DIR='$repo'; PATH='$FAKE_HOME/bin':\$PATH; cd '$FAKE_HOME/cwd'; _install_fisher"
    [ "$status" -eq 0 ]
    grep -qF "git -C \"$repo\" checkout sh/fish_plugins && fisher update" "$FAKE_HOME/fish_args"

    # the recorded git command works from a directory that is not a repo
    cd "$FAKE_HOME/cwd"
    git -C "$repo" checkout sh/fish_plugins
    [ "$(cat "$repo/sh/fish_plugins")" = "original" ]
}

@test '_hyperlink sets plain text when not a tty' {
    run zsh -c "source '$FAKE_HOME/setup.zsh'; _hyperlink https://example.com/x text; print -r -- \"\$REPLY\""
    [ "$output" = "text" ]
}

@test '_hyperlink emits an OSC 8 sequence on a tty' {
    run _tty zsh -c "source '$FAKE_HOME/setup.zsh'; _hyperlink https://example.com/x text; print -r -- \"\$REPLY\""
    [[ "$output" == *$'\e]8;;https://example.com/x\e\\text\e]8;;\e\\'* ]]
}

@test '_hyperlink sets plain text when url is empty' {
    run zsh -c "source '$FAKE_HOME/setup.zsh'; _hyperlink '' text; print -r -- \"\$REPLY\""
    [ "$output" = "text" ]
}

@test '_tilde preserves backslashes' {
    run zsh -c "source '$FAKE_HOME/setup.zsh'; _tilde 'a\\fb'"
    [ "$output" = 'a\fb' ]
}

@test '_repo_url converts ssh and https remotes to a github https url' {
    local repo="$FAKE_HOME/repo"
    git init -q "$repo"

    git -C "$repo" remote add origin git@github.com:arbourd/dotfiles.git
    run zsh -c "source '$FAKE_HOME/setup.zsh'; DIR='$repo'; _repo_url"
    [ "$output" = "https://github.com/arbourd/dotfiles" ]

    git -C "$repo" remote set-url origin https://github.com/arbourd/dotfiles.git
    run zsh -c "source '$FAKE_HOME/setup.zsh'; DIR='$repo'; _repo_url"
    [ "$output" = "https://github.com/arbourd/dotfiles" ]

    git -C "$repo" remote set-url origin ssh://git@github.com/arbourd/dotfiles.git
    run zsh -c "source '$FAKE_HOME/setup.zsh'; DIR='$repo'; _repo_url"
    [ "$output" = "https://github.com/arbourd/dotfiles" ]

    git -C "$repo" remote set-url origin https://github.com/arbourd/dotfiles
    run zsh -c "source '$FAKE_HOME/setup.zsh'; DIR='$repo'; _repo_url"
    [ "$output" = "https://github.com/arbourd/dotfiles" ]

    git -C "$repo" remote set-url origin https://example.com/x/y.git
    run zsh -c "source '$FAKE_HOME/setup.zsh'; DIR='$repo'; _repo_url"
    [ -z "$output" ]
}

@test '_repo_url prints nothing without an origin remote' {
    local repo="$FAKE_HOME/repo"
    git init -q "$repo"
    run zsh -c "source '$FAKE_HOME/setup.zsh'; DIR='$repo'; _repo_url"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test 'command lists stay in sync across dot, completions, and ci' {
    local commands dispatch fish bash zshc ci
    commands="$(cd "$DOTFILES" && ./dot help | awk '/^Commands:/{f=1;next} /^Options:/{f=0} f{print $1}' | sort)"
    [ -n "$commands" ]

    dispatch="$(grep -oE '^    [a-z-]+\)' "$DOTFILES/dot" | tr -d ' )' | sort)"
    [ "$dispatch" = "$commands" ]

    fish="$(sed -n 's/^set -l commands //p' "$DOTFILES/sh/completions/dot.fish" | tr ' ' '\n' | sort)"
    [ "$fish" = "$commands" ]

    bash="$(sed -n 's/.*compgen -W "\([^"]*\)".*/\1/p' "$DOTFILES/sh/completions/dot.bash" | tr ' ' '\n' | sort)"
    [ "$bash" = "$commands" ]

    zshc="$(sed -n "s/^ *'\([a-z-]*\):.*/\1/p" "$DOTFILES/sh/completions/_dot" | sort)"
    [ "$zshc" = "$commands" ]

    ci="$(awk '/command:/{f=1;next} /steps:/{f=0} f && NF{print $2}' "$DOTFILES/.github/workflows/ci.yml" | sort)"
    [ "$ci" = "$(echo "$commands" | grep -vx install)" ]
}

@test '_install runs brew, defaults, fisher, vim in order' {
    run zsh -c "
        source '$FAKE_HOME/setup.zsh'
        _install_brew() { echo brew; }
        _install_defaults() { echo defaults; }
        _install_fisher() { echo fisher; }
        _install_vim() { echo vim; }
        _install
    "
    [ "$status" -eq 0 ]
    [ "$output" = $'brew\ndefaults\nfisher\nvim' ]
}

@test '_install_defaults runs .macOS from the dotfiles dir' {
    mkdir "$FAKE_HOME/repo-mock"
    printf '#!/bin/sh\necho ran-macos\n' > "$FAKE_HOME/repo-mock/.macOS"
    chmod +x "$FAKE_HOME/repo-mock/.macOS"

    run zsh -c "source '$FAKE_HOME/setup.zsh'; DIR='$FAKE_HOME/repo-mock'; _install_defaults"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ran-macos"* ]]
}

@test '_install_brew bundles the Brewfile without a lockfile' {
    mkdir "$FAKE_HOME/bin"
    printf '#!/bin/sh\necho "brew-called $HOMEBREW_BUNDLE_NO_LOCK $*"\n' > "$FAKE_HOME/bin/brew"
    printf '#!/bin/sh\n' > "$FAKE_HOME/bin/curl"
    chmod +x "$FAKE_HOME/bin/"*

    run zsh -c "source '$FAKE_HOME/setup.zsh'; PATH='$FAKE_HOME/bin':\$PATH; _install_brew"
    [ "$status" -eq 0 ]
    [[ "$output" == *"brew-called 1 bundle --file $DOTFILES/Brewfile"* ]]
}

@test '_install_vim hides vim output on success and shows it on failure' {
    mkdir "$FAKE_HOME/bin"
    printf '#!/bin/sh\n' > "$FAKE_HOME/bin/curl"
    printf '#!/bin/sh\necho vim-output\n' > "$FAKE_HOME/bin/vim"
    chmod +x "$FAKE_HOME/bin/"*

    run zsh -c "source '$FAKE_HOME/setup.zsh'; PATH='$FAKE_HOME/bin':\$PATH; _install_vim"
    [ "$status" -eq 0 ]
    [[ "$output" != *"vim-output"* ]]

    run zsh -c "source '$FAKE_HOME/setup.zsh'; PATH='$FAKE_HOME/bin':\$PATH; VERBOSE=1; _install_vim"
    [ "$status" -eq 0 ]
    [[ "$output" == *"vim-output"* ]]

    printf '#!/bin/sh\necho vim-boom\nexit 1\n' > "$FAKE_HOME/bin/vim"
    run zsh -c "source '$FAKE_HOME/setup.zsh'; PATH='$FAKE_HOME/bin':\$PATH; _install_vim"
    [ "$status" -ne 0 ]
    [[ "$output" == *"vim-boom"* ]]
}
