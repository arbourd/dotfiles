#!/usr/bin/env bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo 'Updating submodules...'
(cd $DIR && exec git submodule update --init --recursive)

echo 'Installing fonts...'
(cd $DIR && exec ./fonts/install.sh)

echo 'Installing items via Homebrew...'
(cd $DIR && exec brew bundle)

echo 'Symlinking dotfiles...'
# Atom
mkdir -p ~/.atom
ln -sf $DIR/atom/init.coffee ~/.atom/init.coffee
ln -sf $DIR/atom/keymap.cson ~/.atom/keymap.cson
ln -sf $DIR/atom/styles.less ~/.atom/styles.less

# Fish
mkdir -p ~/.config/fish/functions  # Create directory for fish-shell
ln -sf $DIR/fish/config.fish ~/.config/fish/config.fish
ln -sf $DIR/fish/fishfile ~/.config/fish/fishfile
ln -sf $DIR/fish/functions/docker-clean.fish ~/.config/fish/functions/docker-clean.fish
ln -sf $DIR/fish/functions/git.fish ~/.config/fish/functions/git.fish

# GPG
mkdir -p ~/.gnupg
ln -sf $DIR/gpg/.gpg-agent.conf ~/.gnupg/gpg-agent.conf

# Git
ln -sf $DIR/git/.gitignore_global ~/.gitignore_global
ln -sf $DIR/git/.gitconfig ~/.gitconfig

# Ruby
ln -sf $DIR/ruby/.gemrc ~/.gemrc

# Vim
mkdir -p ~/.vim/bundle  # Create directory for Vundle
ln -sf $DIR/vim/.vimrc ~/.vimrc
ln -sfn $DIR/vim/Vundle.vim ~/.vim/bundle/Vundle.vim

echo 'Updating Vim plugins...'
vim +PluginInstall! +PluginClean! +qall

echo 'Done!'
