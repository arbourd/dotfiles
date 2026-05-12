# dotfiles

Automated environment as code.

## Installation

  1. Install with script

      ```console
      $ curl -sSL https://raw.githubusercontent.com/arbourd/dotfiles/main/dot.sh | zsh -s -- init
      ```

  1. Run `dot`

      ```console
      $ dot
      Usage: dot [COMMAND]
      Commands:
        help              prints this dialog
        init              clones dotfiles to GETPATH (~/src) and symlinks dot.sh to ~/.local/bin
        update            updates the dotfiles repository
        link              symlinks dotfiles and removes stale symlinks

        install           installs all packages
        install-defaults  installs macos defaults
        install-brew      installs homebrew packages
        install-fisher    installs fisher packages
        install-vim       installs vim packages
      ```
