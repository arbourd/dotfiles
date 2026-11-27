# Tests for the claude-settings-audit skill's compare.js, run with:
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

# exec runs argv and returns its status and combined stdout and stderr, trailing newlines trimmed.
def exec [ctx: record, argv: list<string>]: nothing -> record {
    let r = with-env {FAKE_HOME: $ctx.home, DOTFILES: $DOTFILES} {
        run-external ...$argv o+e>| complete
    }
    {status: $r.exit_code, output: ($r.stdout | str replace -r '\n+$' '')}
}

# _skill <ctx> is the scratch copy of the skill's scripts dir.
def _skill [ctx: record]: nothing -> string {
    $"($ctx.home)/repo/.agents/skills/claude-settings-audit/scripts"
}

# _compare_setup <ctx> <settings.jsonc> <settings.json> [config.jsonc] [~/.claude.json] lays out a fake repo and live files for compare.js. Safe to call again mid-test.
# config.jsonc defaults to {}; ~/.claude.json is left absent unless given.
def _compare_setup [ctx: record, repo: string, live: string, config: string = '{}', claude?: string] {
    let skill = _skill $ctx
    mkdir $skill $"($ctx.home)/repo/agents/claude" $"($ctx.home)/.claude"
    $"($config)\n" | save -f $"($ctx.home)/repo/agents/claude/config.jsonc"
    if $claude != null { $"($claude)\n" | save -f $"($ctx.home)/.claude.json" }
    cp $"($DOTFILES)/.agents/skills/claude-settings-audit/scripts/compare.js" $"($DOTFILES)/.agents/skills/claude-settings-audit/scripts/denylist.json" $skill
    $"($repo)\n" | save -f $"($ctx.home)/repo/agents/claude/settings.jsonc"
    $"($live)\n" | save -f $"($ctx.home)/.claude/settings.json"
}

def _compare [ctx: record]: nothing -> record {
    exec $ctx [env $"HOME=($ctx.home)" bun $"(_skill $ctx)/compare.js"]
}

# _section <output> <name> [block] returns the lines under a "## name" heading in one file's block of a compare.js run
# (1 = settings.jsonc, the default; 2 = config.jsonc), joined by newlines, so tests can match a whole section.
def _section [output: string, name: string, block: int = 1]: nothing -> string {
    let header = $"## ($name)"
    $output | lines | reduce -f {files: 0, f: false, out: []} {|l, acc|
        let files = if ($l | str starts-with '# ') { $acc.files + 1 } else { $acc.files }
        if $files != $block {
            {files: $files, f: false, out: $acc.out}
        } else if ($l | str starts-with $header) {
            {files: $files, f: true, out: $acc.out}
        } else if ($l | str starts-with '#') {
            {files: $files, f: false, out: $acc.out}
        } else if $acc.f and ($l | str trim) != '' and $l != '(none)' {
            {files: $files, f: true, out: ($acc.out | append $l)}
        } else {
            {files: $files, f: $acc.f, out: $acc.out}
        }
    } | get out | str join "\n"
}

@test
def "claude-settings-audit compare.js reports nested live drift and tolerates an empty live file" [] {
    let c = $in
    _compare_setup $c "{\n  // c\n  \"enabledPlugins\": { \"a@m\": true },\n  \"env\": { \"A\": \"1\" }\n}" r#'{"enabledPlugins":{"a@m":true,"old@m":true},"env":{"A":"1","B":"2"},"hooks":{"x":1},"theme":"m"}'#

    let r = _compare $c
    assert equal $r.status 0
    # hooks is hidden, and a@m is in both files so nothing is unapplied
    assert equal (_section $r.output 'Live drift') "enabledPlugins.old@m live=true\nenv.B live=\"<redacted>\"\ntheme live=\"m\""
    assert equal (_section $r.output 'Unapplied') ""

    "" | save -f $"($c.home)/.claude/settings.json"
    let r = _compare $c
    assert equal $r.status 0
    assert str contains $r.output r#'enabledPlugins live=undefined merged={"a@m":true}'#

    # a null deletes the key, so a missing live key counts as applied
    _compare_setup $c r#'{ "constructor": null, "theme": null }'# r#'{"theme":"dark","constructor":1}'#
    let r = _compare $c
    assert str contains $r.output r#'theme live="dark" merged=undefined'#
    _compare_setup $c r#'{ "constructor": null, "theme": null }'# r#'{"toString":1}'#
    let r = _compare $c
    assert equal (_section $r.output 'Unapplied') ""
    assert equal (_section $r.output 'Live drift') 'toString live=1'
}

@test
def "claude-settings-audit compare.js flags merges that lose live data, and only those" [] {
    let c = $in
    _compare_setup $c r#'{"theme":"dark","allow":["a"],"gone":null,"obj":{"x":1},"nul":{"x":1},"keep":["a","b","c"]}'# r#'{"theme":"light","allow":["a","b"],"gone":1,"obj":[1],"nul":null,"keep":["a","b"]}'#

    let r = _compare $c
    assert equal $r.status 0
    assert ($r.output | str starts-with '# settings.jsonc → ~/.claude/settings.json')
    # a scalar overwrite, a live null and an array that only adds entries change live but lose nothing
    assert str contains $r.output r#'theme live="light" merged="dark"'#
    assert str contains $r.output r#'nul live=null merged={"x":1}'#
    assert str contains $r.output r#'keep live=["a","b"] merged=["a","b","c"]'#
    assert equal (_section $r.output 'Merge risks') "allow live=[\"a\",\"b\"] merged=[\"a\"]\ngone live=1 merged=undefined\nobj live=[1] merged={\"x\":1}"
}

# compare.js must fail where `dot merge claude` fails, rather than report a clean run.
@test
def "claude-settings-audit compare.js errors on a missing, blank or non-object repo file" [] {
    let c = $in
    _compare_setup $c '{}' r#'{"theme":"dark"}'#
    rm $"($c.home)/repo/agents/claude/settings.jsonc"
    let r = _compare $c
    assert equal $r.status 1
    assert str contains $r.output 'settings.jsonc is missing'

    "" | save -f $"($c.home)/repo/agents/claude/settings.jsonc"
    let r = _compare $c
    assert equal $r.status 1
    assert str contains $r.output 'compare.js: settings.jsonc:'
    assert not ($r.output | str contains '## Unapplied')

    _compare_setup $c '[1]' r#'{"theme":"dark"}'#
    let r = _compare $c
    assert equal $r.status 1
    assert str contains $r.output 'must be a JSON object'
}

# The report must match what `dot merge claude` does: the keys it lists as Unapplied are exactly the keys the real
# _merge_claude_settings changes, and each merged value is what the real merge wrote.
@test
def "claude-settings-audit compare.js predicts what the real merge writes" [] {
    let c = $in
    _compare_setup $c r#'{"theme":"dark","gone":null,"allow":["a"],"obj":{"x":1},"added":{"y":[1,2]},"num":2,"empty":"x","same":"s"}'# r#'{"theme":"light","gone":1,"allow":["a","b"],"obj":[1],"num":1,"empty":{},"same":"s","other":"kept"}'#
    cp $"($c.home)/.claude/settings.json" $"($c.home)/before.json"
    let r = _compare $c
    assert equal $r.status 0
    let predicted = _section $r.output 'Unapplied'
    assert ($predicted != "")

    let m = exec $c [zsh '-c' $"source '($DOTFILES)/dot'; _log\() { :; }; HOME='($c.home)'; DIR='($c.home)/repo'; _merge_claude_settings"]
    assert equal $m.status 0

    let after = $"($c.home)/.claude/settings.json"
    let lines = $predicted | lines
    let keys = $lines | each {|l| $l | str replace -r ' live=.*' '' } | sort | str join ','
    let changed = (exec $c [jq -n -r --slurpfile a $"($c.home)/before.json" --slurpfile b $after
        '[($a[0] + $b[0]) | keys[] | select($a[0][.] != $b[0][.])] | sort | join(",")']).output
    assert equal $keys $changed

    for line in $lines {
        let key = $line | str replace -r ' live=.*' ''
        mut value = $line | str replace -r '^.* merged=' ''
        if $value == undefined { $value = '"undefined"' }
        let got = exec $c [jq -c --arg k $key 'if has($k) then .[$k] else "undefined" end' $after]
        assert equal $got.output $value
    }

    # applied: a second run has nothing left to change or lose
    let r = _compare $c
    assert equal $r.status 0
    assert equal (_section $r.output 'Unapplied') ""
    assert equal (_section $r.output 'Merge risks') ""
}

@test
def "claude-settings-audit compare.js reports config.jsonc against ~/.claude.json and hides app state from its drift" [] {
    let c = $in
    _compare_setup $c '{}' '{}' r#'{"copyOnSelect":false,"leftArrowOpensAgents":false}'# r#'{"copyOnSelect":true,"leftArrowOpensAgents":false,"numStartups":7,"projects":{"/x":{"a":1}},"hasCompletedOnboarding":true,"tipsHistory":{},"someNewSetting":"x"}'#
    let r = _compare $c
    assert equal $r.status 0
    assert str contains $r.output '# config.jsonc → ~/.claude.json'
    assert equal (_section $r.output 'Unapplied' 2) 'copyOnSelect live=true merged=false'
    assert equal (_section $r.output 'Live drift' 2) 'someNewSetting live="x"'
    assert equal (_section $r.output 'Merge risks' 2) ""
    assert equal (_section $r.output 'Unapplied') ""
}

@test
def "claude-settings-audit compare.js flags a config.jsonc merge that loses live data" [] {
    let c = $in
    _compare_setup $c '{}' '{}' '{"x":[1]}' '{"x":[1,2]}'
    let r = _compare $c
    assert equal (_section $r.output 'Merge risks' 2) 'x live=[1,2] merged=[1]'
}

@test
def "claude-settings-audit compare.js redacts secrets and keeps other values" [] {
    let c = $in
    _compare_setup $c r#'{"credentials":{"value":"FAKE_REPO"}}'# r#'{"credentials":{"value":"FAKE_LIVE"},"env":{"NESTED":{"value":"FAKE_ENV"}},"mcpServers":{"x":{"http_headers":{"X-Custom":"FAKE_HEADER"},"headers":{"X-Other":"FAKE_OTHER"}}},"api":{"apiKey":"FAKE_KEY","url":"https://e.x"},"APIKey":"FAKE_ACRONYM","accesstoken":"FAKE_NOSEP","pat":"FAKE_PAT","basicauth":"FAKE_BASICAUTH","includeCoAuthoredBy":false,"preferredAuthMethod":"oauth","maxTokens":8}'#
    let r = _compare $c
    assert equal $r.status 0
    assert not ($r.output | str contains 'FAKE_')
    assert equal (_section $r.output 'Unapplied') 'credentials.value live="<redacted>" merged="<redacted>"'
    assert str contains $r.output 'env live={"NESTED":{"value":"<redacted>"}}'
    assert str contains $r.output 'api live={"apiKey":"<redacted>","url":"https://e.x"}'
    assert str contains $r.output 'APIKey live="<redacted>"'
    assert str contains $r.output 'includeCoAuthoredBy live=false'
    assert str contains $r.output 'preferredAuthMethod live="oauth"'
    assert str contains $r.output 'maxTokens live=8'
}
