#!/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
action="$1"

_init() {
    echo 'Updating submodules...'
    (cd $DIR && exec git submodule update --init --recursive)

    # Fish
    mkdir -p ~/.config/fish/functions  # Create directory for fish-shell
    touch ~/.config/fish/private.fish  # Create private env vars file if doesn't exist

    # Go
    mkdir -p ~/bin
    mkdir -p ~/pkg
    mkdir -p ~/src

    # GPG
    mkdir -p -m 700 ~/.gnupg

    # Vim
    mkdir -p ~/.vim/bundle  # Create directory for Vundle
}

_link() {
    echo 'Symlinking dotfiles...'

    # Fish
    ln -sf $DIR/fish/config.fish ~/.config/fish/config.fish
    ln -sf $DIR/fish/fishfile ~/.config/fish/fishfile
    ln -sf $DIR/fish/functions/git.fish ~/.config/fish/functions/git.fish

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

    # Update and install fisherman plugins
    echo 'Updating and installing fisherman plugins'
    (cd $DIR && exec fish -c "fisher u" && fish -c exec "fisher")

    # Install ruby gems if bundler
    if which -s bundle ; then
        echo 'Installing global ruby packages...'
        (cd $DIR && exec gem update bundler && exec bundle install)
        if test -f "$DIR/Gemfile.lock" ; then
            # Remove root Gemfile.lock
            rm "$DIR/Gemfile.lock"
        fi
    fi

    echo 'Installing global node packages...'
    (npm install -g live-server webtorrent-cli && npm update -g)

    echo 'Updating Vim plugins...'
    (vim +PluginInstall! +PluginClean! +qall)
}

case $action in
    init)
        _init
        ;;
    link)
        _link
        ;;
    install)
        _install
        ;;
    help)
        exit 0
        ;;
    *)
        _init
        _link
        _install
        ;;
esac
