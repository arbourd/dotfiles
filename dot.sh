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

    # nix
    ln -vsf $DIR/nix/nix.conf ~/.config/nix/nix.conf

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

_install_gofish() {
    # Install gofish if missing
    if ! command -v gofish &> /dev/null ; then
        echo 'Installing gofish...'
        curl -fsSL https://raw.githubusercontent.com/fishworks/gofish/main/scripts/install.sh | bash
        gofish init
        gofish rig add https://github.com/arbourd/rig
    fi

    echo 'Installing gofish packages...'
    gofish update
    gofish install direnv
    gofish install flux
    gofish install gh
    gofish install git-get
    gofish install git-sync
    gofish install go
    gofish install goreleaser
    gofish install helm
    gofish install jq
    gofish install kubectl
    gofish install kubectx
    gofish install kubens
    gofish install kubeseal
    gofish install kustomize
    gofish install mkcert
    gofish install ripgrep
    gofish install terraform
    gofish install tflint
    gofish install tfsec
    gofish install trash
    gofish install yq
}

_install_nix() {
    # Install nix if missing
    if ! command -v nix &> /dev/null ; then
        echo 'Installing nix...'
        curl -L https://nixos.org/nix/install | sh -s -- --daemon
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

        echo 'experimental-features = nix-command flakes ca-references' | sudo tee -a /etc/nix/nix.conf
        nix-env -iA nixpkgs.nixUnstable
    fi
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
    _install_gofish
    _install_nix
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
    help)
        _usage
        exit 0
        ;;
    *)
        _usage
        exit 0
        ;;
esac
