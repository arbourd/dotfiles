set -l commands help version init update link install install-defaults install-brew install-fisher install-vim

complete -c dot -f -n "not __fish_seen_subcommand_from $commands" -a help             -d 'Print usage information'
complete -c dot -f -n "not __fish_seen_subcommand_from $commands" -a init             -d 'Clone dotfiles and symlink dot to ~/.local/bin'
complete -c dot -f -n "not __fish_seen_subcommand_from $commands" -a link             -d 'Symlink dotfiles and remove stale symlinks'
complete -c dot -f -n "not __fish_seen_subcommand_from $commands" -a install          -d 'Install all packages'
complete -c dot -f -n "not __fish_seen_subcommand_from $commands" -a install-defaults -d 'Install macOS defaults'
complete -c dot -f -n "not __fish_seen_subcommand_from $commands" -a install-brew     -d 'Install Homebrew packages'
complete -c dot -f -n "not __fish_seen_subcommand_from $commands" -a install-fisher   -d 'Install Fisher packages'
complete -c dot -f -n "not __fish_seen_subcommand_from $commands" -a install-vim      -d 'Install Vim packages'
complete -c dot -f -n "not __fish_seen_subcommand_from $commands" -a update           -d 'Update the dotfiles repository'
complete -c dot -f -n "not __fish_seen_subcommand_from $commands" -a version          -d 'Print the current commit SHA'
