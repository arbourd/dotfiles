#!/usr/bin/env zsh
DIR="$( cd "$( dirname "${(%):-%N}" )" && pwd )"

_usage() {
    echo "Usage: ./dot.sh [COMMAND]
Commands:
  help              prints this dialog
  bootstrap         links and installs
  clone             clones dotfiles to \$GETPATH
  link              symlinks dotfiles
  install           installs all packages

  install-defaults  installs macos defaults
  install-brew      installs homebrew packages
  install-fisher    installs fisher packages
  install-vim       installs vim packages
"
}

_pre() {
    . $DIR/sh/.shrc

    # fish
    mkdir -p ~/.config/fish/functions  # Create directory for fish-shell
    touch ~/.config/fish/private.fish  # Create private env vars file if doesn't exist

    # git-get
    mkdir -p $GETPATH/github.com/arbourd

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

_link() {
    echo 'Symlinking dotfiles...'

    # bash, fish and zsh
    ln -vsf $DIR/sh/.shrc ~/.bash_profile
    ln -vsf $DIR/sh/.shrc ~/.zshrc
    ln -vsf $DIR/sh/config.fish ~/.config/fish/config.fish
    ln -vsf $DIR/sh/fish_plugins ~/.config/fish/fish_plugins

    # git
    ln -vsf $DIR/git/.gitignore_global ~/.gitignore_global
    ln -vsf $DIR/git/.gitconfig ~/.gitconfig

    # gpg
    ln -vsf $DIR/gpg/gpg-agent.conf ~/.gnupg/gpg-agent.conf

    # ssh
    ln -vsf $DIR/ssh/config ~/.ssh/config

    # vim
    ln -vsf $DIR/vim/.vimrc ~/.vimrc
}

_install_defaults() {
    echo 'Setting macOS defaults...'
    $DIR/.macOS
}

_install_brew() {
    # Install Homebrew if missing
    if ! command -v brew &> /dev/null ; then
        echo 'Installing Homebrew...'
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    echo 'Installing Homebrew packages...'
    brew bundle --no-lock --file $DIR/Brewfile
}

_install_fisher() {
    # Install fish if missing
    if ! command -v fish &> /dev/null ; then
        echo 'Installing fish...'
        brew install fish
    fi

    echo 'Updating and installing fisher plugins...'
    fish -c "curl -sL https://git.io/fisher | source && fisher install jorgebucaran/fisher"
    fish -c "fisher update"
}

_install_vim() {
    # Install vundle if missing
    if [ ! -d ~/.vim/bundle/Vundle.vim ]; then
        echo 'Installing vundle...'
        git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
    fi

    echo 'Updating Vim plugins...'
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
    bootstrap)
        _pre
        _link
        _install
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
