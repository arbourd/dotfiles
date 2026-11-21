# Tests for the homebrew-drift skill's compare.js, run with:
#   tests/run

use std/assert
use std/testing *

const DOTFILES = (path self | path dirname | path dirname)

@before-each
def setup [] {
    {home: (mktemp -d)}
}

@after-each
def teardown [] {
    rm -rf $in.home
}

# _compare_setup <ctx> <Brewfile-bundle-list-formula> <cask> <leaves> <installed-formula> <installed-cask> lays out a fake repo
# and a fake brew answering from the given newline-separated lists. Its `info --installed` makes kubectl an alias of kubernetes-cli.
def _compare_setup [ctx: record, formula: string, cask: string, leaves: string, list_formula: string, list_cask: string] {
    let h = $ctx.home
    let skill = $"($h)/repo/.agents/skills/homebrew-drift/scripts"
    mkdir $skill $"($h)/bin"
    cp $"($DOTFILES)/.agents/skills/homebrew-drift/scripts/compare.js" $skill
    "" | save $"($h)/repo/Brewfile"
    $"($formula)\n" | save $"($h)/formula"
    $"($cask)\n" | save $"($h)/cask"
    $"($leaves)\n" | save $"($h)/leaves"
    $"($list_formula)\n" | save $"($h)/list-formula"
    $"($list_cask)\n" | save $"($h)/list-cask"
    r##'#!/bin/sh
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
'## | save -f $"($h)/bin/brew"
    ^chmod +x $"($h)/bin/brew"
}

def _compare [ctx: record]: nothing -> record {
    let h = $ctx.home
    let r = ^env $"FAKE_HOME=($h)" $"BREW=($h)/bin/brew" bun $"($h)/repo/.agents/skills/homebrew-drift/scripts/compare.js" o+e>| complete
    {status: $r.exit_code, output: ($r.stdout | str replace -r '\n+$' '')}
}

# _section <output> <name> returns the lines under a "## name" heading, joined by newlines.
def _section [output: string, name: string]: nothing -> string {
    let header = $"## ($name)"
    $output | lines | reduce -f {f: false, out: []} {|l, acc|
        if ($l | str starts-with $header) {
            {f: true, out: $acc.out}
        } else if ($l | str starts-with '#') {
            {f: false, out: $acc.out}
        } else if $acc.f and ($l | str trim) != '' and $l != '(none)' {
            {f: true, out: ($acc.out | append $l)}
        } else {
            $acc
        }
    } | get out | str join "\n"
}

@test
def "homebrew-drift compare.js reports installed-but-unlisted and listed-but-missing, formulae and casks" [] {
    let c = $in
    _compare_setup $c "git\nwget" "slack\nfirefox" "git\njq\narbourd/tap/awman" "git\njq\nawman\nlibfoo" "slack\nvlc"

    let r = _compare $c
    assert equal $r.status 0
    assert equal (_section $r.output 'Not in Brewfile') "formula jq\nformula arbourd/tap/awman\ncask vlc"
    assert equal (_section $r.output 'Not installed') "formula wget\ncask firefox"
}

@test
def "homebrew-drift compare.js matches tap-qualified names and aliases" [] {
    let c = $in
    _compare_setup $c "arbourd/tap/go\nkubectl" 'x' "go\nkubernetes-cli" "go\nkubernetes-cli" 'x'

    let r = _compare $c
    assert equal $r.status 0
    assert equal (_section $r.output 'Not in Brewfile') ""
    assert equal (_section $r.output 'Not installed') ""
}

@test
def "homebrew-drift compare.js treats a Brewfile entry brew has never heard of as not installed" [] {
    let c = $in
    _compare_setup $c "git\nnot-a-real-tap/x/thing" 'slack' 'git' 'git' 'slack'

    let r = _compare $c
    assert equal $r.status 0
    assert equal (_section $r.output 'Not in Brewfile') ""
    assert equal (_section $r.output 'Not installed') 'formula not-a-real-tap/x/thing'
}

@test
def "homebrew-drift compare.js errors when brew fails" [] {
    let c = $in
    _compare_setup $c 'git' 'slack' 'git' 'git' 'slack'
    "#!/bin/sh\necho boom >&2\nexit 1\n" | save -f $"($c.home)/bin/brew"

    let r = _compare $c
    assert equal $r.status 1
    assert str contains $r.output boom
    assert not ($r.output | str contains '## Not in Brewfile')
}
