_dot() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    if [[ $COMP_CWORD -eq 2 ]]; then
        case ${COMP_WORDS[1]} in
            merge) COMPREPLY=($(compgen -W 'claude codex orca' -- "$cur")) ;;
            install) COMPREPLY=($(compgen -W 'brew defaults fisher vim' -- "$cur")) ;;
        esac
        return
    fi
    [[ $COMP_CWORD -eq 1 ]] || return
    COMPREPLY=($(compgen -W "help init link merge install update version" -- "$cur"))
}

complete -F _dot dot
