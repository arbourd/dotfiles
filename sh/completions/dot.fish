set -l commands help version init update link merge install

# commands are offered until one other than help is typed, so `dot help <TAB>` lists them too
set -l not_help (string match -v help -- $commands)

complete -c dot -f -s h -l help    -d 'Print usage for a command or target'
complete -c dot -f -s v -l verbose -d 'Show full output instead of spinners'

complete -c dot -f -n "not __fish_seen_subcommand_from $not_help" -a help    -d 'Print usage information'
complete -c dot -f -n "not __fish_seen_subcommand_from $not_help" -a init    -d 'Clone dotfiles and symlink dot to ~/.local/bin'
complete -c dot -f -n "not __fish_seen_subcommand_from $not_help" -a link    -d 'Symlink dotfiles and remove stale symlinks'
complete -c dot -f -n "not __fish_seen_subcommand_from $not_help" -a merge   -d 'Merge settings into Claude, Codex and Orca'
complete -c dot -f -n "not __fish_seen_subcommand_from $not_help" -a install -d 'Install all packages'
complete -c dot -f -n "not __fish_seen_subcommand_from $not_help" -a update  -d 'Update the dotfiles repository'
complete -c dot -f -n "not __fish_seen_subcommand_from $not_help" -a version -d 'Print the current commit SHA'

# a target is offered until it has been typed, so several can be given
complete -c dot -f -n "__fish_seen_subcommand_from merge; and not __fish_seen_subcommand_from claude" -a claude -d 'Merge Claude settings'
complete -c dot -f -n "__fish_seen_subcommand_from merge; and not __fish_seen_subcommand_from codex"  -a codex  -d 'Merge Codex config'
complete -c dot -f -n "__fish_seen_subcommand_from merge; and not __fish_seen_subcommand_from orca"   -a orca   -d 'Merge Orca settings'

complete -c dot -f -n "__fish_seen_subcommand_from install; and not __fish_seen_subcommand_from brew"     -a brew     -d 'Install Homebrew packages'
complete -c dot -f -n "__fish_seen_subcommand_from install; and not __fish_seen_subcommand_from defaults" -a defaults -d 'Install macOS defaults'
complete -c dot -f -n "__fish_seen_subcommand_from install; and not __fish_seen_subcommand_from fisher"   -a fisher   -d 'Install Fisher packages'
complete -c dot -f -n "__fish_seen_subcommand_from install; and not __fish_seen_subcommand_from vim"      -a vim      -d 'Install Vim packages'
