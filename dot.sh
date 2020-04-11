#!/usr/bin/env zsh
DIR="$( cd "$( dirname "${(%):-%N}" )" && pwd )"

_usage() {
    echo "Usage: ./dot.sh [COMMAND]
Commands:
  help          prints this dialog
  init          updates submodules and creates directories (if needed)
  link          symlinks dotfiles
  install       installs packages for homebrew, fonts, fish and vim
  bootstrap     initializes, links and installs"
}

_pre() {
    . $DIR/sh/.shrc

    # fish
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

    # fish
    ln -sf $DIR/fish/config.fish ~/.config/fish/config.fish
    ln -sf $DIR/fish/fishfile ~/.config/fish/fishfile
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

_install_fonts() {
    echo 'Installing fonts...'
    (cd $DIR && exec ./fonts/install.sh)
}

_install_brew() {
    # Install Homebrew if missing
    if ! which -s brew ; then
        echo 'Installing Homebrew...'
        ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    fi

    # Install Homebrew packages
    echo 'Installing Homebrew packages...'
    (cd $DIR && exec brew bundle --no-lock)
    (ln -sf $(brew --repository arbourd/tap) $GETPATH/github.com/arbourd/homebrew-tap)
}

_install_fisher() {
    echo 'Updating and installing fisher plugins...'
    curl -sLo ~/.config/fish/functions/fisher.fish --create-dirs git.io/fisher
    (cd $DIR && exec fish -c "fisher")
}

_install_vim() {
    echo 'Updating Vim plugins...'
    (vim +PluginInstall! +PluginClean! +qall)
}

_install() {
    _install_brew
    _install_fonts
    _install_fisher
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
    install-fonts)
        _pre
        _install_fonts
        ;;
    install-fisher)
        _pre
        _install_fisher
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
