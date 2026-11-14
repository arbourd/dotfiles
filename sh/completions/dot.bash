_dot() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if [[ $COMP_CWORD -eq 2 && ${COMP_WORDS[1]} == merge ]]; then
        COMPREPLY=($(compgen -W 'claude codex orca' -- "$cur"))
        return
    fi
    [[ $COMP_CWORD -eq 1 ]] || return
    COMPREPLY=($(compgen -W "help init link merge install install-defaults install-brew install-fisher install-vim update version" -- "$cur"))
}

complete -F _dot dot
