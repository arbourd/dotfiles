#!/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

_usage() {
    echo "Usage: ./dot.sh [COMMAND]
Commands:
  help          prints this dialog
  init          updates submodules and creates directories (if needed)
  link          symlinks dotfiles
  install       installs packages for homebrew, fish shell, ruby, node and vim
  bootstrap     initializes, links and installs"
}

_pre() {
    . $DIR/bash/.bash_profile

    # Fish
    mkdir -p ~/.config/fish/functions  # Create directory for fish-shell
    touch ~/.config/fish/private.fish  # Create private env vars file if doesn't exist

    # git-get
    mkdir -p $GETPATH/github.com/arbourd

    # Go
    mkdir -p ~/go

    # GPG
    mkdir -p -m 700 ~/.gnupg

    # Rust
    mkdir -p ~/.cargo/bin

    # Vim
    mkdir -p ~/.vim/bundle  # Create directory for Vundle
}

_init() {
    echo 'Updating submodules...'
    (cd $DIR && exec git submodule update --init --recursive)
}

_link() {
    echo 'Symlinking dotfiles...'

    # Fish
    ln -sf $DIR/fish/config.fish ~/.config/fish/config.fish
    ln -sf $DIR/fish/fishfile ~/.config/fish/fishfile
    for file in $(ls -1 $DIR/fish/functions); do
        ln -sf $DIR/fish/functions/$file ~/.config/fish/functions/$file
    done

    # Bash
    ln -sf $DIR/bash/.bash_profile ~/.bash_profile

    # Git
    ln -sf $DIR/git/.gitignore_global ~/.gitignore_global
    ln -sf $DIR/git/.gitconfig ~/.gitconfig

    # GPG
    ln -sf $DIR/gpg/gpg-agent.conf ~/.gnupg/gpg-agent.conf

    # Hyper
    ln -sf $DIR/hyper/.hyper.js ~/.hyper.js

    # Ruby
    ln -sf $DIR/ruby/.gemrc ~/.gemrc

    # ssh
    ln -sf $DIR/ssh/config ~/.ssh/config

    # Vim
    ln -sf $DIR/vim/.vimrc ~/.vimrc
    ln -sfn $DIR/vim/Vundle.vim ~/.vim/bundle/Vundle.vim
}

_install() {
    echo 'Installing fonts...'
    (cd $DIR && exec ./fonts/install.sh)

    # Install Homebrew if missing
    if ! which -s brew ; then
        echo 'Installing Homebrew...'
        ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    fi

    # Install Homebrew packages
    echo 'Installing Homebrew packages...'
    (cd $DIR && exec brew bundle)
    (ln -sf $(brew --repository arbourd/tap) $GETPATH/github.com/arbourd/homebrew-tap)

    # Install fisherman and plugins
    echo 'Updating and installing fisherman plugins...'
    curl -sLo ~/.config/fish/functions/fisher.fish --create-dirs git.io/fisher
    (cd $DIR && exec fish -c "fisher")

    # Install ruby gems if bundler
    if which -s bundle ; then
        echo 'Installing global ruby packages...'
        (cd $DIR && exec gem update bundler && exec bundle install)
        if test -f "$DIR/Gemfile.lock" ; then
            # Remove root Gemfile.lock
            rm "$DIR/Gemfile.lock"
        fi
    fi

    echo 'Updating Vim plugins...'
    (vim +PluginInstall! +PluginClean! +qall)
}

case $1 in
    init)
        _pre
        _init
        ;;
    link)
        _pre
        _link
        ;;
    install)
        _pre
        _install
        ;;
    bootstrap)
        _pre
        _init
        _link
        _install
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
