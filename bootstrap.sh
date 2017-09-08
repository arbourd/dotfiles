#!/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo 'Updating submodules...'
(cd $DIR && exec git submodule update --init --recursive)

echo 'Symlinking dotfiles...'

# Fish
mkdir -p ~/.config/fish/functions  # Create directory for fish-shell
ln -sf $DIR/fish/config.fish ~/.config/fish/config.fish
ln -sf $DIR/fish/fishfile ~/.config/fish/fishfile
ln -sf $DIR/fish/functions/git.fish ~/.config/fish/functions/git.fish

# Git
ln -sf $DIR/git/.gitignore_global ~/.gitignore_global
ln -sf $DIR/git/.gitconfig ~/.gitconfig

# Go
mkdir -p ~/go/bin

# GPG
mkdir -p ~/.gnupg
ln -sf $DIR/gpg/gpg-agent.conf ~/.gnupg/gpg-agent.conf

# Hyper
ln -sf $DIR/hyper/.hyper.js ~/.hyper.js

# Ruby
ln -sf $DIR/ruby/.gemrc ~/.gemrc

# Vim
mkdir -p ~/.vim/bundle  # Create directory for Vundle
ln -sf $DIR/vim/.vimrc ~/.vimrc
ln -sfn $DIR/vim/Vundle.vim ~/.vim/bundle/Vundle.vim

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

echo 'Done!'
