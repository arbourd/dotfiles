#!/usr/bin/env zsh
DIR="$(dirname "$(readlink -f "$0")")"

getpath=$(git config --global get.path || echo "")
if [ -z "$getpath" ]; then
    getpath="${GETPATH:-~/src}"
fi

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
"
}

_pre() {
    . "$DIR/sh/.shrc"

    # fish
    mkdir -p ~/.config/fish/functions  # Create directory for fish-shell
    touch ~/.config/fish/private.fish  # Create private env vars file

    # git
    mkdir -p ~/.config/git

    # golang
    mkdir -p ~/go

    # gpg
    mkdir -p -m 700 ~/.gnupg

    # rust
    mkdir -p ~/.cargo/bin

    # ssh
    mkdir -p ~/.ssh

    # vim
    mkdir -p ~/.vim/bundle  # Create directory for Vundle
}

_clone() {
    echo "\n$(tput bold)Cloning dotfiles to $getpath/github.com/arbourd/dotfiles $(tput sgr0)...\n"

    mkdir -p "$getpath/github.com/arbourd"

    git clone https://github.com/arbourd/dotfiles.git "$getpath/github.com/arbourd/dotfiles"
    echo "\n$(tput bold)$getpath/github.com/arbourd/dotfiles$(tput sgr0)"
}

_link() {
    echo "\n$(tput bold)Symlinking dotfiles $(tput sgr0)...\n"

    # bash, fish and zsh
    ln -vsf "$DIR/sh/.shrc" ~/.bash_profile
    ln -vsf "$DIR/sh/.shrc" ~/.zshrc
    ln -vsf "$DIR/sh/config.fish" ~/.config/fish/config.fish
    ln -vsf "$DIR/sh/fish_plugins" ~/.config/fish/fish_plugins

    # git
    ln -vsf "$DIR/git/config" ~/.config/git/config
    ln -vsf "$DIR/git/gitignore" ~/.config/git/gitignore

    # gpg
    ln -vsf "$DIR/gpg/gpg-agent.conf" ~/.gnupg/gpg-agent.conf

    # ssh
    ln -vsf "$DIR/ssh/config" ~/.ssh/config

    # vim
    ln -vsf "$DIR/vim/vimrc" ~/.vim/vimrc
}

_install_defaults() {
    echo "\n$(tput bold)Setting macOS defaults $(tput sgr0)...\n"
    $DIR/.macOS
}

_install_brew() {
    # Install Homebrew if missing
    if ! command -v brew &> /dev/null ; then
        echo "\n$(tput bold)Installing Homebrew $(tput sgr0)...\n"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    echo "\n$(tput bold)Installing Homebrew packages $(tput sgr0)...\n"
    brew bundle --no-lock --file "$DIR/Brewfile"
}

_install_fisher() {
    # Install fish if missing
    if ! command -v fish &> /dev/null ; then
        echo "\n$(tput bold)Installing fish $(tput sgr0)...\n"
        brew install fish
    fi

    echo "\n$(tput bold)Updating and installing fisher plugins $(tput sgr0)...\n"
    fish -c "curl -fsSL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher"
    fish -c "git checkout $DIR/sh/fish_plugins"
    fish -c "fisher update"
}

_install_vim() {
    # Install vundle if missing
    if [ ! -d ~/.vim/bundle/Vundle.vim ]; then
        echo "\n$(tput bold)Installing Vundle $(tput sgr0) ...\n"
        git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
    fi

    echo "\n$(tput bold)Updating Vundle $(tput sgr0)...\n"
    /bin/zsh -c "cd ~/.vim/bundle/Vundle.vim; git pull origin master"

    echo "\n$(tput bold)Updating Vim plugins $(tput sgr0)...\n"
    # Supress attaching to tty
    echo | echo | vim +PluginInstall! +PluginClean! +qall &>/dev/null
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
    help)
        _usage
        exit 0
        ;;
    *)
        _usage
        exit 0
        ;;
esac
