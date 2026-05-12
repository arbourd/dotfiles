_dot() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    [[ $COMP_CWORD -eq 1 ]] || return
    COMPREPLY=($(compgen -W "help init update link install install-defaults install-brew install-fisher install-vim" -- "$cur"))
}

complete -F _dot dot
