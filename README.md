# dotfiles

Automated environment as code.

## Installation

  1. Install with script

      ```console
      $ curl -sSL https://raw.githubusercontent.com/arbourd/dotfiles/main/dot.sh | sh -s -- clone
      ```

  1. Run `dot.sh`

      ```console
      $ ./dot.sh
      Usage: ./dot.sh [COMMAND]
      Commands:
        help              prints this dialog
        clone             clones dotfiles to $GITGET_GETPATH (~/src)
        link              symlinks dotfiles
        install           installs all packages

        install-defaults  installs macos defaults
        install-brew      installs homebrew packages
        install-fisher    installs fisher packages
        install-vim       installs vim packages
      ```
