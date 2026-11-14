set -l commands help version init update link merge install
set -l merge_targets claude codex orca
set -l install_targets brew defaults fisher vim

complete -c dot -f -n "not __fish_seen_subcommand_from $commands" -a help    -d 'Print usage information'
complete -c dot -f -n "not __fish_seen_subcommand_from $commands" -a init    -d 'Clone dotfiles and symlink dot to ~/.local/bin'
complete -c dot -f -n "not __fish_seen_subcommand_from $commands" -a link    -d 'Symlink dotfiles and remove stale symlinks'
complete -c dot -f -n "not __fish_seen_subcommand_from $commands" -a merge   -d 'Merge settings into Claude, Codex and Orca'
complete -c dot -f -n "not __fish_seen_subcommand_from $commands" -a install -d 'Install all packages'
complete -c dot -f -n "not __fish_seen_subcommand_from $commands" -a update  -d 'Update the dotfiles repository'
complete -c dot -f -n "not __fish_seen_subcommand_from $commands" -a version -d 'Print the current commit SHA'

complete -c dot -f -n "__fish_seen_subcommand_from merge; and not __fish_seen_subcommand_from $merge_targets" -a claude -d 'Merge Claude settings'
complete -c dot -f -n "__fish_seen_subcommand_from merge; and not __fish_seen_subcommand_from $merge_targets" -a codex  -d 'Merge Codex config'
complete -c dot -f -n "__fish_seen_subcommand_from merge; and not __fish_seen_subcommand_from $merge_targets" -a orca   -d 'Merge Orca settings'

complete -c dot -f -n "__fish_seen_subcommand_from install; and not __fish_seen_subcommand_from $install_targets" -a brew     -d 'Install Homebrew packages'
complete -c dot -f -n "__fish_seen_subcommand_from install; and not __fish_seen_subcommand_from $install_targets" -a defaults -d 'Install macOS defaults'
complete -c dot -f -n "__fish_seen_subcommand_from install; and not __fish_seen_subcommand_from $install_targets" -a fisher   -d 'Install Fisher packages'
complete -c dot -f -n "__fish_seen_subcommand_from install; and not __fish_seen_subcommand_from $install_targets" -a vim      -d 'Install Vim packages'
