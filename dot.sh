#!/usr/bin/env zsh
DIR="$( cd "$( dirname "${(%):-%N}" )" && pwd )"

_usage() {
    echo "Usage: ./dot.sh [COMMAND]
Commands:
  help              prints this dialog
  bootstrap         links and installs
  link              symlinks dotfiles
  install           installs all packages

  install-defaults  installs macos defaults
  install-brew      installs homebrew
  install-fisher    installs fisher packages
  install-gofish    installs gofish packages
  install-nix       installs nix
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

    # nix
    mkdir -p ~/.config/nix

    # rust
    mkdir -p ~/.cargo/bin

    # vim
    mkdir -p ~/.vim/bundle  # Create directory for Vundle
}

_link() {
    echo 'Symlinking dotfiles...'

    # bash and zsh
    ln -sf $DIR/sh/.shrc ~/.bash_profile
    ln -sf $DIR/sh/.shrc ~/.zshrc

    # fish
    ln -sf $DIR/fish/config.fish ~/.config/fish/config.fish
    ln -sf $DIR/fish/fish_plugins ~/.config/fish/fish_plugins

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
    (cd $DIR && exec fish -c "curl -sL https://git.io/fisher | source && fisher install jorgebucaran/fisher")
    (cd $DIR && exec fish -c "fisher update")
}

_install_gofish() {
    # Install gofish if missing
    if ! command -v gofish &> /dev/null ; then
        echo 'Installing gofish...'
        curl -fsSL https://raw.githubusercontent.com/fishworks/gofish/main/scripts/install.sh | bash
        gofish init
        gofish rig add https://github.com/arbourd/rig
    fi

    echo 'Installing gofish packages...'
    (gofish update)
    (gofish install act)
    (gofish install flux)
    (gofish install gh)
    (gofish install git-get)
    (gofish install git-sync)
    (gofish install go)
    (gofish install gofish)
    (gofish install goreleaser)
    (gofish install helm)
    (gofish install jq)
    (gofish install kubectl)
    (gofish install kubeseal)
    (gofish install kustomize)
    (gofish install kubectx)
    (gofish install kubens)
    (gofish install ripgrep)
    (gofish install stern)
    (gofish install terraform)
    (gofish install tflint)
    (gofish install tilt)
    (gofish install trash)
    (gofish install yq)
}

_install_nix() {
    # Install nix if missing
    if ! command -v nix &> /dev/null ; then
        echo 'Installing nix...'
        sh <(curl -L https://nixos.org/nix/install) --darwin-use-unencrypted-nix-store-volume

        nix-env -iA nixpkgs.nixUnstable
        echo 'experimental-features = nix-command flakes ca-references' >> ~/.config/nix/nix.conf
    fi
}

_install_vim() {
    # Install vundle if missing
    if [ ! -d ~/.vim/bundle/Vundle.vim ]; then
        echo 'Installing vundle...'
        git clone https://github.com/VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
    fi

    echo 'Updating Vim plugins...'
    (echo | echo | vim +PluginInstall! +PluginClean! +qall &>/dev/null)
}

_install() {
    _install_brew
    _install_defaults
    _install_fisher
    _install_gofish
    _install_nix
    _install_vim
}

case $1 in
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
    install-nix)
        _pre
        _install_nix
        ;;
    install-vim)
        _pre
        _install_vim
        ;;
    bootstrap)
        _pre
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
