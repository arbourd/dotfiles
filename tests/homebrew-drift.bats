#!/usr/bin/env bats

load helpers

setup() { common_setup; }
teardown() { common_teardown; }

# _compare_setup <Brewfile-bundle-list-formula> <cask> <leaves> <installed-formula> <installed-cask> lays out a fake repo and a fake brew
# answering from the given newline-separated lists. Its `info --installed` makes kubectl an alias of kubernetes-cli.
_compare_setup() {
    skill="$FAKE_HOME/repo/.agents/skills/homebrew-drift/scripts"
    mkdir -p "$skill" "$FAKE_HOME/bin"
    cp "$DOTFILES/.agents/skills/homebrew-drift/scripts/"compare.js "$skill/"
    : > "$FAKE_HOME/repo/Brewfile"
    printf '%s\n' "$1" > "$FAKE_HOME/formula"
    printf '%s\n' "$2" > "$FAKE_HOME/cask"
    printf '%s\n' "$3" > "$FAKE_HOME/leaves"
    printf '%s\n' "$4" > "$FAKE_HOME/list-formula"
    printf '%s\n' "$5" > "$FAKE_HOME/list-cask"
    cat > "$FAKE_HOME/bin/brew" <<'SH'
#!/bin/sh
d="$FAKE_HOME"
case "$1 $2" in
    "bundle list") case "$3" in --formula) cat "$d/formula" ;; --cask) cat "$d/cask" ;; esac ;;
    "leaves --installed-on-request") cat "$d/leaves" ;;
    "list --formula") cat "$d/list-formula" ;;
    "list --cask") cat "$d/list-cask" ;;
    "info --json=v2")
        printf '{"formulae":['; sep=; while read -r n; do
            [ -n "$n" ] || continue
            case "$n" in kubernetes-cli) al='"kubectl"' ;; *) al= ;; esac
            printf '%s{"name":"%s","full_name":"%s","aliases":[%s],"oldnames":[]}' "$sep" "${n##*/}" "$n" "$al"; sep=,
        done < "$d/list-formula"
        printf '],"casks":['; sep=; while read -r n; do
            [ -n "$n" ] || continue
            printf '%s{"token":"%s","full_token":"%s","old_tokens":[]}' "$sep" "${n##*/}" "$n"; sep=,
        done < "$d/list-cask"
        printf ']}' ;;
    *) echo "unexpected: $*" >&2; exit 1 ;;
esac
SH
    chmod +x "$FAKE_HOME/bin/brew"
}

_compare() {
    run env FAKE_HOME="$FAKE_HOME" BREW="$FAKE_HOME/bin/brew" bun "$skill/compare.js"
}

# _section <name> prints the lines under a "## name" heading.
_section() {
    awk -v header="## $1" 'index($0, header) == 1 { in_section = 1; next } /^#/ { in_section = 0 } in_section && NF && $0 != "(none)"' <<< "$output"
}

@test 'homebrew-drift compare.js reports installed-but-unlisted and listed-but-missing, formulae and casks' {
    _compare_setup $'git\nwget' $'slack\nfirefox' $'git\njq\narbourd/tap/awman' $'git\njq\nawman\nlibfoo' $'slack\nvlc'

    _compare
    [ "$status" -eq 0 ]
    [ "$(_section 'Not in Brewfile')" = $'formula jq\nformula arbourd/tap/awman\ncask vlc' ]
    [ "$(_section 'Not installed')" = $'formula wget\ncask firefox' ]
}

@test 'homebrew-drift compare.js matches tap-qualified names and aliases' {
    _compare_setup $'arbourd/tap/go\nkubectl' 'x' $'go\nkubernetes-cli' $'go\nkubernetes-cli' 'x'

    _compare
    [ "$status" -eq 0 ]
    [ -z "$(_section 'Not in Brewfile')" ]
    [ -z "$(_section 'Not installed')" ]
}

@test 'homebrew-drift compare.js treats a Brewfile entry brew has never heard of as not installed' {
    _compare_setup $'git\nnot-a-real-tap/x/thing' 'slack' 'git' 'git' 'slack'

    _compare
    [ "$status" -eq 0 ]
    [ -z "$(_section 'Not in Brewfile')" ]
    [ "$(_section 'Not installed')" = 'formula not-a-real-tap/x/thing' ]
}

@test 'homebrew-drift compare.js errors when brew fails' {
    _compare_setup 'git' 'slack' 'git' 'git' 'slack'
    printf '#!/bin/sh\necho boom >&2\nexit 1\n' > "$FAKE_HOME/bin/brew"
    _compare
    [ "$status" -eq 1 ]
    [[ "$output" == *'boom'* ]]
    [[ "$output" != *'## Not in Brewfile'* ]]
}

@test 'homebrew-drift skill is linked for Claude' {
    [ -f "$DOTFILES/.claude/skills/homebrew-drift/SKILL.md" ]
}
