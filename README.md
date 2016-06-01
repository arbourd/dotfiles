# dotfiles

A collection / backup of my dotfiles

* Atom
* fish-shell
* git
* iTerm2
* Vim

## Installation

  1. Clone the repo

    ```bash
    $ git clone git://github.com/arbourd/dotfiles
    ```

  1. Init & update submodules

    ```bash
    $ git submodule update --init --recursive
    ```

  1. Install fonts

    ```bash
    $ bash ./fonts/install.sh
    ```

  1. Brew bundle (assumes Homebrew is installed)

    ```bash
    $ brew bundle
    ```

  1. Link dotfiles

    ```bash
    # Atom
    $ ln -s $PWD/atom/ ~/.atom

    # Fish
    $ mkdir -p ~/.config/fish  # Create directory for fish-shell
    $ ln -s $PWD/fish/config.fish ~/.config/fish/config.fish
    $ ln -s $PWD/fish/fishfile ~/.config/fish/fishfile

    # Git
    $ ln -s $PWD/git/.gitignore_global ~/.gitignore_global
    $ ln -s $PWD/git/.gitconfig ~/.gitconfig

    # Vim
    $ ln -s $PWD/vim/.vimrc ~/.vimrc
    $ mkdir -p ~/.vim/bundle  # Create directory for Vundle
    $ ln -s $PWD/vim/Vundle.vim ~/.vim/bundle/Vundle.vim
    ```

  1. Install `vim` plugins

    ```bash
    $ vim +PluginInstall! +PluginClean! +qall
    ```

## License

Public Domain
