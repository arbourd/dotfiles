_dot() {
    local cur="${COMP_WORDS[COMP_CWORD]}" cmd="${COMP_WORDS[1]}" word=$COMP_CWORD

    if [[ $cur == -* ]]; then
        COMPREPLY=($(compgen -W '-h --help -v --verbose' -- "$cur"))
        return
    fi

    if [[ $COMP_CWORD -eq 1 || ( $cmd == help && $COMP_CWORD -eq 2 ) ]]; then
        COMPREPLY=($(compgen -W "help init link merge install update version" -- "$cur"))
        return
    fi

    # `dot help <command> <target>` completes like `dot <command> <target>`
    if [[ $cmd == help ]]; then
        cmd="${COMP_WORDS[2]}"
        word=$((COMP_CWORD - 1))
    fi

    [[ $word -ge 2 ]] || return
    case $cmd in
        merge) COMPREPLY=($(compgen -W 'claude codex orca rex' -- "$cur")) ;;
        install) COMPREPLY=($(compgen -W 'brew defaults fisher vim' -- "$cur")) ;;
    esac
}

complete -F _dot dot
