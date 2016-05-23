# dotfiles

A collection / backup of my dotfiles

* Atom
* Fish
* gitignore
* iTerm 2
* Vim

## Installation

  1. Clone the repo

      `$ git clone git://github.com/arbourd/dotfiles`

  2. Update submodules

      `$ git submodule update --init --recursive`

  3. Install fonts

      `$ bash ./fonts/install.sh`

  4. Copy dotfiles

      `$ cp -r atom/.atom fish/.config git/ vim/.vim ~/`

  5. Install `vim` plugins

      `$ vim +BundleUpdate +BundleInstall! +BundleClean +qall`

## License

Public Domain
