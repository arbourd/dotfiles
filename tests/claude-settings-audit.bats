#!/usr/bin/env bats

load helpers

setup() { common_setup; }
teardown() { common_teardown; }

# _compare_setup <settings.jsonc> <settings.json> [config.jsonc] [~/.claude.json] lays out a fake repo and live files for compare.js. Safe to call again mid-test.
# config.jsonc defaults to {}; ~/.claude.json is left absent unless given.
_compare_setup() {
    skill="$FAKE_HOME/repo/.agents/skills/claude-settings-audit/scripts"
    mkdir -p "$skill" "$FAKE_HOME/repo/agents/claude" "$FAKE_HOME/.claude"
    printf '%s\n' "${3:-{\}}" > "$FAKE_HOME/repo/agents/claude/config.jsonc"
    if [ -n "${4:-}" ]; then printf '%s\n' "$4" > "$FAKE_HOME/.claude.json"; fi
    cp "$DOTFILES/.agents/skills/claude-settings-audit/scripts/"{compare.js,denylist.json} "$skill/"
    printf '%s\n' "$1" > "$FAKE_HOME/repo/agents/claude/settings.jsonc"
    printf '%s\n' "$2" > "$FAKE_HOME/.claude/settings.json"
}

_compare() {
    run env HOME="$FAKE_HOME" bun "$skill/compare.js"
}

# _section <name> [block] prints the lines under a "## name" heading in one file's block of the last compare.js run (1 = settings.jsonc, the default; 2 = config.jsonc), so tests can match a whole section.
_section() {
    awk -v header="## $1" -v block="${2:-1}" '/^# / { files++ } files > block { exit } files == block && index($0, header) == 1 { in_section = 1; next } /^#/ { in_section = 0 } in_section && NF && $0 != "(none)"' <<< "$output"
}

@test 'claude-settings-audit compare.js reports nested live drift and tolerates an empty live file' {
    _compare_setup $'{\n  // c\n  "enabledPlugins": { "a@m": true },\n  "env": { "A": "1" }\n}' \
        '{"enabledPlugins":{"a@m":true,"old@m":true},"env":{"A":"1","B":"2"},"hooks":{"x":1},"theme":"m"}'

    _compare
    [ "$status" -eq 0 ]
    # hooks is hidden, and a@m is in both files so nothing is unapplied
    [ "$(_section 'Live drift')" = $'enabledPlugins.old@m live=true\nenv.B live="2"\ntheme live="m"' ]
    [ -z "$(_section 'Unapplied')" ]

    : > "$FAKE_HOME/.claude/settings.json"
    _compare
    [ "$status" -eq 0 ]
    [[ "$output" == *'enabledPlugins live=undefined merged={"a@m":true}'* ]]

    # a null deletes the key, so a missing live key counts as applied
    _compare_setup '{ "constructor": null, "theme": null }' '{"theme":"dark","constructor":1}'
    _compare
    [[ "$output" == *'theme live="dark" merged=undefined'* ]]
    _compare_setup '{ "constructor": null, "theme": null }' '{"toString":1}'
    _compare
    [ -z "$(_section 'Unapplied')" ]
    [ "$(_section 'Live drift')" = 'toString live=1' ]
}

@test 'claude-settings-audit compare.js flags merges that lose live data, and only those' {
    _compare_setup '{"theme":"dark","allow":["a"],"gone":null,"obj":{"x":1},"nul":{"x":1},"keep":["a","b","c"]}' \
        '{"theme":"light","allow":["a","b"],"gone":1,"obj":[1],"nul":null,"keep":["a","b"]}'

    _compare
    [ "$status" -eq 0 ]
    # the output names the repo file it read (a suffix, since bun resolves the macOS /var symlink)
    [[ "$output" == '# settings.jsonc → ~/.claude/settings.json'* ]]
    # a scalar overwrite, a live null and an array that only adds entries change live but lose nothing
    [[ "$output" == *'theme live="light" merged="dark"'* ]]
    [[ "$output" == *'nul live=null merged={"x":1}'* ]]
    [[ "$output" == *'keep live=["a","b"] merged=["a","b","c"]'* ]]
    [ "$(_section 'Merge risks')" = $'allow live=["a","b"] merged=["a"]\ngone live=1 merged=undefined\nobj live=[1] merged={"x":1}' ]
}

# compare.js must fail where `dot merge claude` fails, rather than report a clean run.
@test 'claude-settings-audit compare.js errors on a missing, blank or non-object repo file' {
    _compare_setup '{}' '{"theme":"dark"}'
    rm "$FAKE_HOME/repo/agents/claude/settings.jsonc"
    _compare
    [ "$status" -eq 1 ]
    [[ "$output" == *'settings.jsonc is missing'* ]]

    : > "$FAKE_HOME/repo/agents/claude/settings.jsonc"
    _compare
    [ "$status" -eq 1 ]
    [[ "$output" == *'compare.js: settings.jsonc:'* ]]
    [[ "$output" != *'## Unapplied'* ]]

    _compare_setup '[1]' '{"theme":"dark"}'
    _compare
    [ "$status" -eq 1 ]
    [[ "$output" == *'must be a JSON object'* ]]
}

@test 'claude-settings-audit compare.js treats a live file that is not an object as lost, and a live null as nothing' {
    _compare_setup '{"theme":"dark"}' '[1]'
    _compare
    [ "$status" -eq 0 ]
    [[ "$output" == *'(whole file) live=[1] is not a JSON object'* ]]
    [[ "$output" == *'theme live=undefined merged="dark"'* ]]

    _compare_setup '{"theme":"dark"}' 'null'
    _compare
    [ "$status" -eq 0 ]
    [ -z "$(_section 'Merge risks')" ]
    [[ "$output" == *'theme live=undefined merged="dark"'* ]]
}

@test 'claude-settings-audit compare.js does not flag a live null that the repo also nulls' {
    _compare_setup '{"a":null}' '{"a":null}'
    _compare
    [ "$status" -eq 0 ]
    [ "$(_section 'Unapplied')" = 'a live=null merged=undefined' ]
    [ -z "$(_section 'Merge risks')" ]
}

@test 'claude-settings-audit compare.js marks a truncated value with an ellipsis' {
    local long=$(printf 'x%.0s' {1..80})
    _compare_setup "{\"long\":\"$long\"}" '{}'
    _compare
    [ "$status" -eq 0 ]
    [[ "$output" == *'…'* ]]
    [[ "$output" != *"$long"* ]]
}

@test 'claude-settings-audit compare.js does not call replacing an empty object or array a loss' {
    _compare_setup '{"e":"x","f":"y"}' '{"e":{},"f":[]}'
    _compare
    [ "$status" -eq 0 ]
    [ "$(_section 'Unapplied')" = $'e live={} merged="x"\nf live=[] merged="y"' ]
    [ -z "$(_section 'Merge risks')" ]
}

@test 'claude-settings-audit compare.js hides a top-level hooks key from drift but not a nested one' {
    _compare_setup '{"env":{"A":"1"}}' '{"hooks":{"x":1},"apiKeyHelper":"k","model":"m","env":{"A":"1","hooks":2}}'
    _compare
    [ "$status" -eq 0 ]
    [ "$(_section 'Live drift')" = 'env.hooks live=2' ]
}

@test 'claude-settings-audit compare.js errors on a missing denylist or one lacking a repo file' {
    _compare_setup '{}' '{}'
    rm "$skill/denylist.json"
    _compare
    [ "$status" -eq 1 ]
    [[ "$output" == *'compare.js: denylist.json:'* ]]

    printf '%s\n' '{"settings.jsonc":[]}' > "$skill/denylist.json"
    _compare
    [ "$status" -eq 1 ]
    [[ "$output" == *'denylist.json must list config.jsonc as an array'* ]]
    [[ "$output" != *'## Unapplied'* ]]
}

@test 'claude-settings-audit compare.js reports an unparseable live file as one error line' {
    _compare_setup '{"theme":"dark"}' '{ "a": '
    _compare
    [ "$status" -eq 1 ]
    [[ "$output" == *'compare.js: ~/.claude/settings.json'* ]]
    [[ "$output" != *'    at '* ]]
}

# The report must match what `dot merge claude` does: the keys it lists as Unapplied are exactly the keys the real
# _merge_claude_settings changes, and each merged value is what the real merge wrote.
@test 'claude-settings-audit compare.js predicts what the real merge writes' {
    _compare_setup '{"theme":"dark","gone":null,"allow":["a"],"obj":{"x":1},"added":{"y":[1,2]},"num":2,"empty":"x","same":"s"}' \
        '{"theme":"light","gone":1,"allow":["a","b"],"obj":[1],"num":1,"empty":{},"same":"s","other":"kept"}'
    cp "$FAKE_HOME/.claude/settings.json" "$FAKE_HOME/before.json"
    _compare
    [ "$status" -eq 0 ]
    local predicted=$(_section 'Unapplied')
    [ -n "$predicted" ]

    run zsh -c "source '$DOTFILES/dot'; _log() { :; }; HOME='$FAKE_HOME'; DIR='$FAKE_HOME/repo'; _merge_claude_settings"
    [ "$status" -eq 0 ]

    local after="$FAKE_HOME/.claude/settings.json" line key value
    local keys=$(sed 's/ live=.*//' <<< "$predicted" | sort | paste -sd, -)
    local changed=$(jq -n -r --slurpfile a "$FAKE_HOME/before.json" --slurpfile b "$after" \
        '[($a[0] + $b[0]) | keys[] | select($a[0][.] != $b[0][.])] | sort | join(",")')
    [ "$keys" = "$changed" ]

    while IFS= read -r line; do
        key=${line%% live=*}
        value=${line##* merged=}
        [ "$value" = undefined ] && value='"undefined"'
        [ "$(jq -c --arg k "$key" 'if has($k) then .[$k] else "undefined" end' "$after")" = "$value" ]
    done <<< "$predicted"

    # applied: a second run has nothing left to change or lose
    _compare
    [ -z "$(_section 'Unapplied')" ]
    [ -z "$(_section 'Merge risks')" ]
}

@test 'claude-settings-audit compare.js reports a changed nested key by its dotted path, and only that key' {
    _compare_setup '{"env":{"A":"2","C":"3"}}' '{"env":{"A":"1","B":"2"}}'
    _compare
    [ "$status" -eq 0 ]
    [ "$(_section 'Unapplied')" = $'env.A live="1" merged="2"\nenv.C live=undefined merged="3"' ]
    [ -z "$(_section 'Merge risks')" ]
}

# __proto__ is an own key once JSON.parse reads it, but a plain lookup on a file that lacks it finds Object.prototype.
@test 'claude-settings-audit compare.js reads only own keys, so an inherited name is a new key' {
    _compare_setup '{"__proto__":{"x":1}}' '{}'
    _compare
    [ "$status" -eq 0 ]
    [ "$(_section 'Unapplied')" = '__proto__ live=undefined merged={"x":1}' ]
}

@test 'claude-settings-audit compare.js reports config.jsonc against ~/.claude.json and hides app state from its drift' {
    _compare_setup '{}' '{}' '{"copyOnSelect":false,"leftArrowOpensAgents":false}' \
        '{"copyOnSelect":true,"leftArrowOpensAgents":false,"numStartups":7,"projects":{"/x":{"a":1}},"hasCompletedOnboarding":true,"tipsHistory":{},"someNewSetting":"x"}'
    _compare
    [ "$status" -eq 0 ]
    [[ "$output" == *'# config.jsonc → ~/.claude.json'* ]]
    [ "$(_section 'Unapplied' 2)" = 'copyOnSelect live=true merged=false' ]
    [ "$(_section 'Live drift' 2)" = 'someNewSetting live="x"' ]
    [ -z "$(_section 'Merge risks' 2)" ]
    [ -z "$(_section 'Unapplied')" ]
}

@test 'claude-settings-audit compare.js flags a config.jsonc merge that loses live data' {
    _compare_setup '{}' '{}' '{"x":[1]}' '{"x":[1,2]}'
    _compare
    [ "$(_section 'Merge risks' 2)" = 'x live=[1,2] merged=[1]' ]
}

@test 'claude-settings-audit compare.js prints nothing when config.jsonc is missing' {
    _compare_setup '{"theme":"dark"}' '{}'
    rm "$FAKE_HOME/repo/agents/claude/config.jsonc"
    _compare
    [ "$status" -eq 1 ]
    [[ "$output" == *'config.jsonc is missing'* ]]
    [[ "$output" != *'## Unapplied'* ]]
}
