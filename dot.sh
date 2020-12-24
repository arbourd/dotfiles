#!/usr/bin/env zsh
DIR="$( cd "$( dirname "${(%):-%N}" )" && pwd )"

_usage() {
    echo "Usage: ./dot.sh [COMMAND]
Commands:
  help          prints this dialog
  init          updates submodules and creates directories (if needed)
  link          symlinks dotfiles
  install       installs packages
  bootstrap     initializes, links and installs"
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

    # vim
    mkdir -p ~/.vim/bundle  # Create directory for Vundle
}

_init() {
    echo 'Updating submodules...'
    (cd $DIR && exec git submodule update --init --recursive)
}

_link() {
    echo 'Symlinking dotfiles...'

    # fish
    ln -sf $DIR/fish/config.fish ~/.config/fish/config.fish
    ln -sf $DIR/fish/fish_plugins ~/.config/fish/fish_plugins
    for file in $(ls -1 $DIR/fish/functions); do
        ln -sf $DIR/fish/functions/$file ~/.config/fish/functions/$file
    done

    # bash and zsh
    ln -sf $DIR/sh/.shrc ~/.bash_profile
    ln -sf $DIR/sh/.shrc ~/.zshrc

    # git
    ln -sf $DIR/git/.gitignore_global ~/.gitignore_global
    ln -sf $DIR/git/.gitconfig ~/.gitconfig

    # gpg
    ln -sf $DIR/gpg/gpg-agent.conf ~/.gnupg/gpg-agent.conf

    # ssh
    ln -sf $DIR/ssh/config ~/.ssh/config

    # vim
    ln -sf $DIR/vim/.vimrc ~/.vimrc
    ln -sfn $DIR/vim/Vundle.vim ~/.vim/bundle/Vundle.vim
}

_install_defaults() {
    echo 'Setting macOS defaults...'
    (cd $DIR && exec ./.macOS)
}

_install_brew() {
    # Install Homebrew if missing
    if ! command -v brew &> /dev/null ; then
        echo 'Installing Homebrew...'
        ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    fi

    echo 'Installing Homebrew packages...'
    (cd $DIR && exec brew bundle --no-lock)
}

_install_fisher() {
    echo 'Updating and installing fisher plugins...'
    curl -sLo ~/.config/fish/functions/fisher.fish --create-dirs git.io/fisher
    (cd $DIR && exec fish -c "fisher update")
}

_install_gofish() {
    # Install gofish if missing
    if ! command -v gofish &> /dev/null ; then
        echo 'Installing gofish...'
        curl -fsSL https://raw.githubusercontent.com/fishworks/gofish/main/scripts/install.sh | bash
        gofish rig add https://github.com/arbourd/rig
    fi

    echo 'Installing gofish packages...'
    (gofish update)
    (gofish install flux)
    (gofish install gh)
    (gofish install git-get)
    (gofish install git-sync)
    (gofish install go)
    (gofish install gofish)
    (gofish install helm)
    (gofish install kubectl)
    (gofish install kubectx)
    (gofish install terraform)
    (gofish install trash)
}

_install_vim() {
    echo 'Updating Vim plugins...'
    (vim +PluginInstall! +PluginClean! +qall)
}

_install() {
    _install_defaults
    _install_brew
    _install_fisher
    _install_gofish
    _install_vim
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
    install-gofish)
        _pre
        _install_gofish
        ;;
    install-vim)
        _pre
        _install_vim
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
