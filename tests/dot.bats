#!/usr/bin/env bats

setup() {
    DOTFILES="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    FAKE_HOME="$(mktemp -d)"

    sed '/^case /,$d' "$DOTFILES/dot" > "$FAKE_HOME/dot"

    cat > "$FAKE_HOME/setup.zsh" <<SETUP
source '${FAKE_HOME}/dot'
_log() { :; }
unset GETPATH
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
    [[ "$output" == *"abc1234"* ]]
    [[ "$output" == *"up to date"* ]]
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
    [[ "$output" == *"abc1234"* ]]
    [[ "$output" == *"def5678"* ]]
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
    [ -L "$FAKE_HOME/.config/zed/settings.json" ]
    [ "$(readlink "$FAKE_HOME/.config/zed/settings.json")" = "$DOTFILES/zed/settings.json" ]

    [ -d "$FAKE_HOME/.gnupg" ]
    [ "$(_perms "$FAKE_HOME/.gnupg")" = "drwx------" ]
    [ -f "$FAKE_HOME/.config/fish/private.fish" ]
    [ -f "$FAKE_HOME/.config/git/private" ]
}

@test 'link-agents creates agent symlinks with renaming' {
    mkdir -p "$FAKE_HOME/repo-mock/agents/claude" \
             "$FAKE_HOME/repo-mock/agents/personas" \
             "$FAKE_HOME/repo-mock/agents/skills/skill-a" \
             "$FAKE_HOME/repo-mock/agents/skills/skill-b"
    touch "$FAKE_HOME/repo-mock/agents/claude/statusline.sh" \
          "$FAKE_HOME/repo-mock/agents/personas/helper.md" \
          "$FAKE_HOME/repo-mock/agents/skills/skill-a/SKILL.md" \
          "$FAKE_HOME/repo-mock/agents/skills/skill-b/SKILL.md"

    zsh -c "source '$FAKE_HOME/setup.zsh'; DIR='$FAKE_HOME/repo-mock'; _link_agents" > /dev/null

    [ -L "$FAKE_HOME/.claude/statusline.sh" ]
    [ "$(readlink "$FAKE_HOME/.claude/statusline.sh")" = "$FAKE_HOME/repo-mock/agents/claude/statusline.sh" ]

    [ -L "$FAKE_HOME/.claude/agents/helper.md" ]
    [ "$(readlink "$FAKE_HOME/.claude/agents/helper.md")" = "$FAKE_HOME/repo-mock/agents/personas/helper.md" ]
    [ -L "$FAKE_HOME/.gemini/agents/helper.md" ]
    [ "$(readlink "$FAKE_HOME/.gemini/agents/helper.md")" = "$FAKE_HOME/repo-mock/agents/personas/helper.md" ]
    [ -L "$FAKE_HOME/.pi/agent/prompts/helper.md" ]
    [ "$(readlink "$FAKE_HOME/.pi/agent/prompts/helper.md")" = "$FAKE_HOME/repo-mock/agents/personas/helper.md" ]
    [ -L "$FAKE_HOME/.copilot/agents/helper.agent.md" ]
    [ "$(readlink "$FAKE_HOME/.copilot/agents/helper.agent.md")" = "$FAKE_HOME/repo-mock/agents/personas/helper.md" ]

    [ -L "$FAKE_HOME/.claude/skills/skill-a" ]
    [ "$(readlink "$FAKE_HOME/.claude/skills/skill-a")" = "$FAKE_HOME/repo-mock/agents/skills/skill-a" ]
    [ -L "$FAKE_HOME/.agents/skills/skill-a" ]
    [ "$(readlink "$FAKE_HOME/.agents/skills/skill-a")" = "$FAKE_HOME/repo-mock/agents/skills/skill-a" ]
    [ -L "$FAKE_HOME/.claude/skills/skill-b" ]
    [ "$(readlink "$FAKE_HOME/.claude/skills/skill-b")" = "$FAKE_HOME/repo-mock/agents/skills/skill-b" ]
    [ -L "$FAKE_HOME/.agents/skills/skill-b" ]
    [ "$(readlink "$FAKE_HOME/.agents/skills/skill-b")" = "$FAKE_HOME/repo-mock/agents/skills/skill-b" ]
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

    ln -sf "$DOTFILES/nonexistent" "$FAKE_HOME/stale-link"
    zsh -c "source '$FAKE_HOME/setup.zsh'; _remove_stale_link '$FAKE_HOME/stale-link' '$DOTFILES/'"
    [ -z "$(readlink "$FAKE_HOME/stale-link" 2>/dev/null)" ]
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
    mkdir -p "$space_repo/sh"
    touch "$space_repo/sh/.shrc"

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
    [[ "$output" == *"Usage: dot [COMMAND]"* ]]
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
    [[ "$output" == *"Usage: dot [COMMAND]"* ]]
}

@test 'dot with unknown command exits 1 with error and usage on stderr' {
    run zsh -c "cd '$DOTFILES' && ./dot unknown 2>&1 >/dev/null"
    [ "$status" -eq 1 ]
    [[ "$output" == *'error: unknown command: "unknown"'* ]]
    [[ "$output" == *"Usage: dot [COMMAND]"* ]]
}
