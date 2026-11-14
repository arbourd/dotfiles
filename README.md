# dotfiles

Automated environment as code.

## Installation

  1. Install with script

      ```console
      $ curl -sSL https://raw.githubusercontent.com/arbourd/dotfiles/main/dot | zsh -s -- init
      ```

  1. Run `dot`

      ```console
      $ dot help
      Usage: dot [-v|--verbose] [COMMAND]
      Commands:
        help              prints this dialog
        init              clones dotfiles to GETPATH (~/src) and symlinks dot to ~/.local/bin
        install [TARGET]  installs all packages (or one: brew|defaults|fisher|vim)
        link              symlinks dotfiles and removes stale symlinks
        merge [TARGET]    merges settings into claude, codex and orca (or one: claude|codex|orca)
        update            updates the dotfiles repository
        version           prints the current commit sha
      Options:
        -v, --verbose     shows full output instead of spinners
        -h, --help        prints usage for a command or target (e.g. install brew)
      ```
