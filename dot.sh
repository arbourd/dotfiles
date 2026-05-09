#!/usr/bin/env zsh
set -euo pipefail

DIR="${0:A:h}"

getpath=$(git config --global get.path || echo "")
if [ -z "$getpath" ]; then
    getpath="${GETPATH:-~/src}"
fi

_log() {
    echo "\n$(tput bold)$*$(tput sgr0)\n"
}

_require() {
    if ! command -v "$1" &> /dev/null; then
        echo "Error: '$1' is required but not installed." >&2
        exit 1
    fi
}

_remove_stale_link() {
    local link=$1 prefix=$2 target
    [ -L "$link" ] || return 0
    target=$(readlink "$link")
    [[ "$target" == "$prefix"* ]] || return 0
    [ -e "$target" ] && return 0
    echo "$link"
    unlink "$link"
}

_clean_dir() {
    local prefix=$1 dir link; shift
    for dir in "$@"; do
        for link in "$dir"/*(DN@); do
            _remove_stale_link "$link" "$prefix"
        done
    done
}

_usage() {
    echo "Usage: ./dot.sh [COMMAND]
Commands:
  help              prints this dialog
  clone             clones dotfiles to GETPATH (${getpath})
  link              symlinks dotfiles

  install           installs all packages
  install-defaults  installs macos defaults
  install-brew      installs homebrew packages
  install-fisher    installs fisher packages
  install-vim       installs vim packages

  clean             removes stale dotfile symlinks
"
}

_pre() {
    # Ensure environment is loaded
    [ -f "$DIR/sh/.shrc" ] && . "$DIR/sh/.shrc"

    # agents
    mkdir -p ~/.claude/skills ~/.agents/skills
    mkdir -p ~/.claude/agents ~/.gemini/agents ~/.config/opencode/agents ~/.copilot/agents ~/.pi/agent/prompts

    # fish
    mkdir -p ~/.config/fish/functions
    touch ~/.config/fish/private.fish

    # git
    mkdir -p ~/.config/git
    touch ~/.config/git/private

    # ghostty
    mkdir -p ~/.config/ghostty

    # golang
    mkdir -p ~/go

    # gpg
    mkdir -p -m 700 ~/.gnupg

    # rust
    mkdir -p ~/.cargo/bin

    # ssh
    mkdir -p ~/.ssh

    # vim
    mkdir -p ~/.vim

    # zed
    mkdir -p ~/.config/zed
}

_clone() {
    _require git
    local target="$getpath/github.com/arbourd/dotfiles"
    _log "Cloning dotfiles to $target ..."

    if [ -d "$target" ]; then
        echo "Directory already exists. Pulling latest changes..."
        git -C "$target" pull
    else
        mkdir -p "$(dirname "$target")"
        git clone https://github.com/arbourd/dotfiles.git "$target"
    fi

    _log "$target"
}

_link() {
    _log "Symlinking dotfiles"

    # bash, fish and zsh
    ln -vsf "$DIR/sh/.shrc" ~/.bash_profile
    ln -vsf "$DIR/sh/.shrc" ~/.bashrc
    ln -vsf "$DIR/sh/.shrc" ~/.zshrc
    ln -vsf "$DIR/sh/config.fish" ~/.config/fish/config.fish
    ln -vsf "$DIR/sh/fish_plugins" ~/.config/fish/fish_plugins

    # ghostty
    ln -vsf "$DIR/ghostty/config" ~/.config/ghostty/config

    # git
    ln -vsf "$DIR/git/config" ~/.config/git/config
    ln -vsf "$DIR/git/gitignore" ~/.config/git/gitignore

    # gpg
    ln -vsf "$DIR/gpg/gpg-agent.conf" ~/.gnupg/gpg-agent.conf

    # ssh
    ln -vsf "$DIR/ssh/config" ~/.ssh/config

    # vim
    ln -vsf "$DIR/vim/vimrc" ~/.vim/vimrc

    # zed
    ln -vsf "$DIR/zed/settings.json" ~/.config/zed/settings.json

    _log "Symlinking agent dotfiles"
    _link_agents
}

_link_agents() {
    local skill
    for skill in "$DIR/agents/skills"/*(/N); do
        ln -vsf "$skill" ~/.claude/skills/
        ln -vsf "$skill" ~/.agents/skills/
    done

    local persona
    for persona in "$DIR/agents/personas"/*.md(N); do
        ln -vsf "$persona" ~/.claude/agents/
        ln -vsf "$persona" ~/.gemini/agents/
        ln -vsf "$persona" ~/.config/opencode/agents/
        ln -vsf "$persona" ~/.pi/agent/prompts/
        ln -vsf "$persona" ~/.copilot/agents/"${persona:t:r}.agent.md"
    done
}

_clean() {
    _log "Cleaning stale dotfile symlinks"
    _clean_dir "$DIR/" ~ ~/.config/fish ~/.config/ghostty ~/.config/git ~/.config/zed ~/.gnupg ~/.ssh ~/.vim
    _clean_dir "$DIR/agents/" ~/.claude/skills ~/.agents/skills ~/.claude/agents ~/.gemini/agents ~/.config/opencode/agents ~/.copilot/agents ~/.pi/agent/prompts
}

_install_defaults() {
    _log "Setting macOS defaults"
    "$DIR/.macOS"
}

_install_brew() {
    _require curl
    # Install Homebrew if missing
    if ! command -v brew &> /dev/null ; then
        _log "Installing Homebrew"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    _log "Installing Homebrew packages"
    HOMEBREW_BUNDLE_NO_LOCK=1 brew bundle --file "$DIR/Brewfile"
}

_install_fisher() {
    _require brew
    _require curl
    _require git

    # Install fish if missing
    if ! command -v fish &> /dev/null ; then
        _log "Installing fish"
        brew install fish
    fi

    _log "Updating and installing fisher plugins"
    fish -c "curl -fsSL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher"
    fish -c "git checkout \"$DIR/sh/fish_plugins\" && fisher update"
}

_install_vim() {
    _require vim
    _require curl

    _log "Updating vim-plug"
    curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
        https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

    _log "Updating Vim plugins"
    # pipe two newlines to dismiss vim-plug prompts without a tty
    echo | echo | vim +PlugUpdate +PlugClean! +qall &>/dev/null
}

_install() {
    _install_brew
    _install_defaults
    _install_fisher
    _install_vim
}

case $1 in
    clone)
        _clone
        ;;
    link)
        _pre
        _link
        ;;
    install)
        _pre
        _install
        ;;
    install-brew)
        _pre
        _install_brew
        ;;
    install-defaults)
        _pre
        _install_defaults
        ;;
    install-fisher)
        _pre
        _install_fisher
        ;;
    install-vim)
        _pre
        _install_vim
        ;;
    clean)
        _clean
        ;;
    help)
        _usage
        exit 0
        ;;
    *)
        _usage
        exit 0
        ;;
esac
