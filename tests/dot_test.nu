# Tests for dot and the repo's config files, run with:
#   tests/run
#
# zsh snippets are raw strings; they reach the repo and scratch home through the
# DOTFILES and FAKE_HOME env vars that `run` exports, instead of nu interpolation.

use std/assert
use std/testing *

const DOTFILES = (path self | path dirname | path dirname)

@before-each
def setup [] {
    let home = (mktemp -d)
    [
        r#'source "$DOTFILES/dot"'#
        "_log() { :; }"
        "unset GETPATH TERM_PROGRAM"
        r#'HOME="$FAKE_HOME"'#
        r#'DIR="$DOTFILES"'#
    ] | str join "\n" | save $"($home)/setup.zsh"
    {home: $home}
}

@after-each
def teardown [] {
    rm -rf $in.home
}

# exec runs argv and returns its status and combined stdout and stderr, trailing newlines trimmed.
def exec [ctx: record, argv: list<string>, --cwd: string, --tty]: nothing -> record {
    let argv = if $tty { tty-wrap $argv } else { $argv }
    let cwd = $cwd | default $env.PWD
    let r = with-env {FAKE_HOME: $ctx.home, DOTFILES: $DOTFILES} {
        cd $cwd
        # empty stdin: parallel `script` runs would otherwise share the caller's terminal and fight over its mode
        "" | run-external ...$argv o+e>| complete
    }
    {status: $r.exit_code, output: ($r.stdout | str replace -r '\n+$' '')}
}

# zsh runs a script after sourcing setup.zsh, so dot's functions are loaded with HOME faked.
def zsh [ctx: record, script: string, --tty]: nothing -> record {
    exec $ctx --tty=$tty [zsh '-c' $"source \"$FAKE_HOME/setup.zsh\"\n($script)"]
}

# zsh-ok runs zsh and fails the test on a non-zero exit.
def zsh-ok [ctx: record, script: string] {
    let r = zsh $ctx $script
    if $r.status != 0 { error make {msg: $"exit ($r.status): ($r.output)"} }
}

# tty-wrap runs argv with stdout attached to a pty.
def tty-wrap [argv: list<string>]: nothing -> list<string> {
    if $nu.os-info.name == macos {
        [script -q /dev/null ...$argv]
    } else {
        let quoted = $argv | each {|a| $"'($a | str replace -a "'" "'\\''")'" } | str join ' '
        [script -qec $quoted /dev/null]
    }
}

def perms [p: string]: nothing -> string {
    if $nu.os-info.name == macos { ^stat -f %Sp $p } else { ^stat -c %A $p }
}

def is-link [p: string]: nothing -> bool { ($p | path type) == symlink }

def assert-link [link: string, target: string] {
    assert (is-link $link) $"not a symlink: ($link)"
    assert equal (^readlink $link) $target
}

# stub writes an executable script to $FAKE_HOME/bin.
def stub [ctx: record, name: string, body: string] {
    mkdir $"($ctx.home)/bin"
    $"#!/bin/sh\n($body)" | save -f $"($ctx.home)/bin/($name)"
    ^chmod +x $"($ctx.home)/bin/($name)"
}

def head-sha []: nothing -> string { ^git -C $DOTFILES rev-parse --short HEAD }

# between mimics awk '/start/{f=1;next} /stop/{f=0} f': lines after a start line, up to a stop line.
def between [start: string, --stop: string]: list<string> -> list<string> {
    $in | reduce -f {f: false, out: []} {|l, acc|
        if $l =~ $start {
            {f: true, out: $acc.out}
        } else if $stop != null and $l =~ $stop {
            {f: false, out: $acc.out}
        } else if $acc.f {
            {f: true, out: ($acc.out | append $l)}
        } else {
            $acc
        }
    } | get out
}

def field [n: int]: string -> string {
    $in | str trim | split row -r '\s+' | get -o $n | default ''
}

@test
def "_ensure leaves existing files untouched" [] {
    let c = $in
    mkdir $"($c.home)/cfg"
    "secret\n" | save $"($c.home)/cfg/private"
    zsh-ok $c r#'_ensure "$FAKE_HOME/cfg/private"'#
    assert equal (open --raw $"($c.home)/cfg/private") "secret\n"
}

@test
def "_require fails when command is missing" [] {
    let r = zsh $in r#'_require "missing_cmd_$(date +%s)" 2>&1'#
    assert equal $r.status 1
    assert str contains $r.output "Error:"
}

@test
def "init creates parent dirs, clones, and symlinks dot when target missing" [] {
    let c = $in
    let target = $"($c.home)/src/github.com/arbourd/dotfiles"
    zsh-ok $c r#'
        GETPATH="$FAKE_HOME/src"
        git() { echo "$*" > "$FAKE_HOME/git_args"; }
        _init
    '#
    assert equal ($"($c.home)/src/github.com/arbourd" | path type) dir
    assert equal (open --raw $"($c.home)/git_args" | str trim) $"clone https://github.com/arbourd/dotfiles.git ($target)"
    assert-link $"($c.home)/.local/bin/dot" $"($target)/dot"
}

@test
def "init pulls and re-symlinks dot when target already exists" [] {
    let c = $in
    let target = $"($c.home)/src/github.com/arbourd/dotfiles"
    mkdir $target
    zsh-ok $c r#'
        GETPATH="$FAKE_HOME/src"
        git() { echo "$*" > "$FAKE_HOME/git_args"; }
        _init
    '#
    assert equal (open --raw $"($c.home)/git_args" | str trim) $"-C ($target) pull"
    assert-link $"($c.home)/.local/bin/dot" $"($target)/dot"
}

@test
def "update reports up to date when HEAD does not change" [] {
    let r = zsh $in r#'
        git() {
            if [[ "$*" == *'rev-parse --short HEAD'* ]]; then echo 'abc1234'; return 0; fi
            if [[ "$*" == *'pull --quiet'* ]]; then return 0; fi
            command git "$@"
        }
        _update
    '#
    assert equal $r.status 0
    assert str contains $r.output "pulling dotfiles"
    assert str contains $r.output "dotfiles abc1234 (up to date)"
}

@test
def "update reports old and new hashes when HEAD changes" [] {
    let r = zsh $in r#'
        flag="$FAKE_HOME/git_pull_flag"
        git() {
            if [[ "$*" == *'pull --quiet'* ]]; then touch "$flag"; return 0; fi
            if [[ "$*" == *'rev-parse --short HEAD'* ]]; then
                if [[ -e "$flag" ]]; then echo 'def5678'; else echo 'abc1234'; fi
                return 0
            fi
            command git "$@"
        }
        _update
    '#
    assert equal $r.status 0
    assert str contains $r.output updated
    assert str contains $r.output "dotfiles abc1234 → def5678"
}

@test
def "link creates dotfile symlinks" [] {
    let c = $in
    let h = $c.home
    let d = $DOTFILES
    zsh-ok $c '_link'

    let links = [
        [.bash_profile sh/.shrc]
        [.bashrc sh/.shrc]
        [.zshrc sh/.shrc]
        [.config/fish/config.fish sh/config.fish]
        [.config/fish/fish_plugins sh/fish_plugins]
        [.config/fish/completions/dot.fish sh/completions/dot.fish]
        [.local/share/bash-completion/completions/dot sh/completions/dot.bash]
        [.zsh/completions/_dot sh/completions/_dot]
        [.config/ghostty/config ghostty/config]
        [.config/git/config git/config]
        [.config/git/gitignore git/gitignore]
        [.gnupg/gpg-agent.conf gpg/gpg-agent.conf]
        [.ssh/config ssh/config]
        [.vim/vimrc vim/vimrc]
        [.orca/keybindings.json orca/keybindings.json]
        [.config/zed/settings.json zed/settings.json]
    ]
    for l in $links { assert-link $"($h)/($l.0)" $"($d)/($l.1)" }
    for fn in (glob $"($d)/sh/functions/*.fish") {
        assert-link $"($h)/.config/fish/functions/($fn | path basename)" $fn
    }

    assert equal ($"($h)/.gnupg" | path type) dir
    assert equal (perms $"($h)/.gnupg") 'drwx------'
    assert equal ($"($h)/.config/fish/private.fish" | path type) file
    assert equal (perms $"($h)/.config/fish/private.fish") '-rw-------'
    assert equal ($"($h)/.config/git/private" | path type) file
    assert equal (perms $"($h)/.config/git/private") '-rw-------'
}

@test
def "link is idempotent and preserves private files" [] {
    let c = $in
    let h = $c.home
    zsh-ok $c '_link'
    "secret\n" | save -f $"($h)/.config/fish/private.fish"
    "secret\n" | save -f $"($h)/.config/git/private"

    assert equal (zsh $c '_link').status 0

    assert-link $"($h)/.zshrc" $"($DOTFILES)/sh/.shrc"
    assert-link $"($h)/.claude/AGENTS.md" $"($DOTFILES)/agents/AGENTS.md"
    assert-link $"($h)/.claude/CLAUDE.md" $"($DOTFILES)/agents/claude/CLAUDE.md"
    assert equal (open --raw $"($h)/.config/fish/private.fish") "secret\n"
    assert equal (open --raw $"($h)/.config/git/private") "secret\n"
    assert not ($"($h)/.claude/skills/skills" | path exists)
}

@test
def "link-agents creates agent symlinks with renaming" [] {
    let c = $in
    let h = $c.home
    let m = $"($h)/repo-mock/agents"
    mkdir $"($m)/claude" $"($m)/personas" $"($m)/skills/skill-a" $"($m)/skills/skill-b" $"($m)/codex"
    for f in [AGENTS.md claude/CLAUDE.md claude/statusline.nu personas/helper.md skills/skill-a/SKILL.md skills/skill-b/SKILL.md codex/config.toml] {
        touch $"($m)/($f)"
    }
    "{}\n" | save $"($m)/claude/settings.jsonc"

    zsh-ok $c r#'DIR="$FAKE_HOME/repo-mock"; _link_agents'#

    assert-link $"($h)/.claude/statusline.nu" $"($m)/claude/statusline.nu"
    assert-link $"($h)/.claude/CLAUDE.md" $"($m)/claude/CLAUDE.md"

    for dir in [.claude/agents .gemini/agents .pi/agent/prompts .config/opencode/agents] {
        assert-link $"($h)/($dir)/helper.md" $"($m)/personas/helper.md"
    }
    for skill in [skill-a skill-b] {
        assert-link $"($h)/.claude/skills/($skill)" $"($m)/skills/($skill)"
        assert-link $"($h)/.agents/skills/($skill)" $"($m)/skills/($skill)"
    }
    for f in [.claude/AGENTS.md .gemini/GEMINI.md .codex/AGENTS.md .pi/agent/AGENTS.md] {
        assert-link $"($h)/($f)" $"($m)/AGENTS.md"
    }
}

@test
def "merge-claude-settings deep-merges over a live settings.json instead of symlinking it" [] {
    let c = $in
    let h = $c.home
    mkdir $"($h)/repo-mock/agents/claude" $"($h)/repo-mock/agents/codex" $"($h)/.claude"
    "{}\n" | save $"($h)/repo-mock/agents/claude/config.jsonc"
    touch $"($h)/repo-mock/agents/codex/config.toml"
    r#'{
  "theme": "dark",
  "editor": { "theme": "repo-theme" },
  "ignorePatterns": ["repo-pattern"]
}
'# | save $"($h)/repo-mock/agents/claude/settings.jsonc"
    r#'{
  "hooks": { "SessionStart": [{ "matcher": "", "hooks": [] }] },
  "editor": { "theme": "live-theme", "fontSize": 14 },
  "ignorePatterns": ["live-pattern"]
}
'# | save $"($h)/.claude/settings.json"

    zsh-ok $c r#'DIR="$FAKE_HOME/repo-mock"; _merge_claude_settings'#

    let f = $"($h)/.claude/settings.json"
    assert equal ($f | path type) file
    let s = open $f
    assert equal $s.theme dark
    assert equal $s.hooks.SessionStart [{matcher: "", hooks: []}]
    # nested objects deep-merge with the repo winning on conflicting keys
    assert equal $s.editor.theme repo-theme
    assert equal $s.editor.fontSize 14
    # arrays are replaced wholesale by the repo's, not unioned
    assert equal $s.ignorePatterns [repo-pattern]
}

@test
def "update-claude-marketplaces syncs every marketplace" [] {
    let c = $in
    let h = $c.home
    stub $c claude $"echo \"$*\" >> \"($h)/claude_args\"\n"

    zsh-ok $c r#'PATH="$FAKE_HOME/bin:$PATH"; _update_claude_marketplaces'#

    assert equal (open --raw $"($h)/claude_args" | lines) ["plugin marketplace update"]
}

@test
def "update-claude-marketplaces skips when claude is not installed" [] {
    let c = $in
    let r = zsh $c 'PATH=/usr/bin:/bin; _update_claude_marketplaces'
    assert equal $r.status 0
    assert str contains $r.output "claude not installed"
}

@test
def "update-claude-marketplaces warns and continues when the update fails" [] {
    let c = $in
    stub $c claude "exit 1\n"
    let r = zsh $c r#'PATH="$FAKE_HOME/bin:$PATH"; _update_claude_marketplaces; echo after'#
    assert equal $r.status 0
    assert str contains $r.output "update failed"
    assert str contains $r.output "after"
}

@test
def "merge stops when the claude settings write fails" [] {
    let c = $in
    let r = zsh $c r#'
        _merge_claude_settings() { return 1; }
        _update_claude_marketplaces() { echo update_claude_marketplaces; }
        _merge_codex_config() { echo merge_codex_config; }
        _merge
    '#
    assert not equal $r.status 0
    assert not ($r.output | str contains update_claude_marketplaces)
    assert not ($r.output | str contains merge_codex_config)
}

@test
def "link does not merge settings" [] {
    let c = $in
    let h = $c.home
    mkdir $"($h)/repo-mock/agents/claude" $"($h)/repo-mock/agents/codex" $"($h)/repo-mock/sh"
    "{}\n" | save $"($h)/repo-mock/agents/claude/config.jsonc"
    touch $"($h)/repo-mock/sh/.shrc"
    "{\"theme\":\"dark\"}\n" | save $"($h)/repo-mock/agents/claude/settings.jsonc"

    zsh-ok $c r#'DIR="$FAKE_HOME/repo-mock"; _link'#

    assert not ($"($h)/.claude/settings.json" | path exists)
    assert not ($"($h)/.codex/config.toml" | path exists)
}

@test
def "merge runs a single target and rejects unknown ones" [] {
    let c = $in
    let h = $c.home
    mkdir $"($h)/repo-mock/agents/claude"
    "{}\n" | save $"($h)/repo-mock/agents/claude/config.jsonc"
    "{\"theme\":\"dark\"}\n" | save $"($h)/repo-mock/agents/claude/settings.jsonc"

    stub $c claude ""
    zsh-ok $c r#'PATH="$FAKE_HOME/bin:$PATH"; DIR="$FAKE_HOME/repo-mock"; _merge claude'#
    assert equal ($"($h)/.claude/settings.json" | path type) file
    assert not ($"($h)/.codex/config.toml" | path exists)

    let r = zsh $c '_merge nope 2>&1'
    assert equal $r.status 1
    assert str contains $r.output 'unknown merge target: "nope"'
}

@test
def "merge-claude-settings handles an empty settings.json and sets 0600" [] {
    let c = $in
    let f = $"($c.home)/.claude/settings.json"
    mkdir $"($c.home)/repo-mock/agents/claude" $"($c.home)/.claude"
    "{}\n" | save $"($c.home)/repo-mock/agents/claude/config.jsonc"
    "{\"effortLevel\": \"high\"}\n" | save $"($c.home)/repo-mock/agents/claude/settings.jsonc"
    "" | save $f
    ^chmod 644 $f

    zsh-ok $c r#'DIR="$FAKE_HOME/repo-mock"; _merge_claude_settings'#

    assert equal (open $f).effortLevel high
    assert equal (perms $f) '-rw-------'
}

@test
def "merge-claude-settings merges config.jsonc into .claude.json and keeps app state" [] {
    let c = $in
    let f = $"($c.home)/.claude.json"
    mkdir $"($c.home)/repo-mock/agents/claude"
    "{}\n" | save $"($c.home)/repo-mock/agents/claude/settings.jsonc"
    "{\"copyOnSelect\": false}\n" | save $"($c.home)/repo-mock/agents/claude/config.jsonc"
    "{\"copyOnSelect\": true, \"numStartups\": 5, \"projects\": {\"/x\": {\"a\": 1}}}\n" | save $f

    zsh-ok $c r#'DIR="$FAKE_HOME/repo-mock"; _merge_claude_settings'#

    assert equal (^jq -c '[.copyOnSelect, .numStartups, .projects."/x".a]' $f) '[false,5,1]'
    assert equal (perms $f) '-rw-------'
}

@test
def "merge-codex-config keeps existing keys and layers the repo tables on top" [] {
    let c = $in
    let f = $"($c.home)/.codex/config.toml"
    mkdir $"($c.home)/repo-mock/agents/codex" $"($c.home)/.codex"
    r#'[marketplaces.demo]
source_type = "git"
ref = "v2"
'# | save $"($c.home)/repo-mock/agents/codex/config.toml"
    r#'model = "local-model"

[marketplaces.demo]
ref = "v1"

[projects."/tmp/x"]
trust_level = "trusted"
'# | save $f

    zsh-ok $c r#'DIR="$FAKE_HOME/repo-mock"; _merge_codex_config'#

    assert not (is-link $f)
    let t = open --raw $f | from toml
    assert equal $t.model local-model
    assert equal ($t.projects | get "/tmp/x" | get trust_level) trusted
    assert equal $t.marketplaces.demo.ref v2
    assert equal (perms $f) '-rw-------'
}

@test
def "merge-codex-config creates config.toml when none exists" [] {
    let c = $in
    mkdir $"($c.home)/repo-mock/agents/codex"
    "[plugins.\"a@b\"]\nenabled = true\n" | save $"($c.home)/repo-mock/agents/codex/config.toml"

    zsh-ok $c r#'DIR="$FAKE_HOME/repo-mock"; _merge_codex_config'#

    let t = open --raw $"($c.home)/.codex/config.toml" | from toml
    assert equal ($t.plugins | get "a@b" | get enabled) true
}

@test
def "repo codex config.toml pins every marketplace to a ref" [] {
    let markets = open --raw $"($DOTFILES)/agents/codex/config.toml" | from toml | get marketplaces | values
    assert ($markets | all {|m|
        ($m.ref? | default '') != '' and ($m.source? | default '') =~ '^https://github\.com/[^/]+/[^/]+\.git$'
    })
}

# jsonc-query evaluates expr with j bound to the file's JSONC, parsed by sqlite.
def jsonc-query [file: string, expr: string]: nothing -> string {
    ^sqlite3 ':memory:' (["WITH f(j) AS (SELECT json(CAST(readfile('" $file "') AS TEXT))) SELECT " $expr " FROM f"] | str join)
}

@test
def "repo claude settings.jsonc has no hooks key" [] {
    assert equal (jsonc-query $"($DOTFILES)/agents/claude/settings.jsonc" "json_type(j, '$.hooks') IS NULL") "1"
}

@test
def "repo claude settings.jsonc marketplace pins still match the Renovate regexes" [] {
    let c = $in
    let file = $"($DOTFILES)/agents/claude/settings.jsonc"
    let pins = jsonc-query $file "(SELECT count(*) FROM json_each(j, '$.extraKnownMarketplaces'))" | into int
    assert ($pins > 0)
    # Every pin must match one of the configured regexes, run as Renovate does over the raw file.
    let r = exec $c [bun '-e' r#'
        const fs = require("fs");
        const [renovate, file] = process.argv.slice(1);
        const text = fs.readFileSync(file, "utf8");
        const regexes = JSON.parse(fs.readFileSync(renovate, "utf8")).customManagers
            .filter((m) => m.managerFilePatterns.includes("agents/claude/settings.jsonc"))
            .flatMap((m) => m.matchStrings)
            .map((r) => new RegExp(r, "g"));
        const matchedRepos = regexes.flatMap((r) => [...text.matchAll(r)].map((m) => m.groups.depName));
        console.log(new Set(matchedRepos).size);
    '# $"($DOTFILES)/.github/renovate.json" $file]
    assert equal $r.status 0
    assert equal ($r.output | ansi strip | into int) $pins
}

@test
def "merge-claude-settings strips comments without touching strings that look like comments" [] {
    let c = $in
    mkdir $"($c.home)/repo-mock/agents/claude" $"($c.home)/.claude"
    "{}\n" | save $"($c.home)/repo-mock/agents/claude/config.jsonc"
    r#'{
  // line comment with "quotes" and a trailing comma,
  "url": "https://example.com//path", // after a value
  /* block
     comment { "hooks": [] } */
  "glob": "src/**/*.ts",
  "escaped": "a \"// not\" comment \\",
  "block": "/* not a comment */",
  "nested": { /* inline */ "theme": "repo" }
}
'# | save $"($c.home)/repo-mock/agents/claude/settings.jsonc"
    r#'{
  // a comment Claude Code tolerates in the live file
  "local": "kept"
}
'# | save $"($c.home)/.claude/settings.json"

    assert equal (zsh $c r#'DIR="$FAKE_HOME/repo-mock"; _merge_claude_settings'#).status 0

    assert equal (^jq -c . $"($c.home)/.claude/settings.json") r#'{"local":"kept","url":"https://example.com//path","glob":"src/**/*.ts","escaped":"a \"// not\" comment \\","block":"/* not a comment */","nested":{"theme":"repo"}}'#
}

@test
def "merge-claude-settings replaces a symlinked settings.json instead of writing through it" [] {
    let c = $in
    let f = $"($c.home)/.claude/settings.json"
    mkdir $"($c.home)/repo-mock/agents/claude" $"($c.home)/.claude"
    "{}\n" | save $"($c.home)/repo-mock/agents/claude/config.jsonc"
    "{\"effortLevel\": \"high\"}\n" | save $"($c.home)/repo-mock/agents/claude/settings.jsonc"
    "{\"local\": \"kept\"}\n" | save $"($c.home)/target.json"
    ^ln -s $"($c.home)/target.json" $f

    assert equal (zsh $c r#'DIR="$FAKE_HOME/repo-mock"; _merge_claude_settings'#).status 0
    assert not (is-link $f)
    assert equal (^jq -c . $f) '{"local":"kept","effortLevel":"high"}'
    assert equal (open --raw $"($c.home)/target.json") "{\"local\": \"kept\"}\n"
}

@test
def "merge-claude-settings fails and leaves settings.json untouched on invalid JSONC" [] {
    let c = $in
    mkdir $"($c.home)/repo-mock/agents/claude" $"($c.home)/.claude"
    "{}\n" | save $"($c.home)/repo-mock/agents/claude/config.jsonc"
    "{\n  /* unterminated\n  \"theme\": \"dark\"\n}\n" | save $"($c.home)/repo-mock/agents/claude/settings.jsonc"
    "{\"local\":\"kept\"}\n" | save $"($c.home)/.claude/settings.json"

    assert not equal (zsh $c r#'DIR="$FAKE_HOME/repo-mock"; _merge_claude_settings'#).status 0
    assert equal (open --raw $"($c.home)/.claude/settings.json") "{\"local\":\"kept\"}\n"
}

@test
def "_remove_stale_link guards and removal" [] {
    let c = $in
    let h = $c.home
    let remove = {|name| zsh-ok $c $"_remove_stale_link \"$FAKE_HOME/($name)\" \"$DOTFILES/\"" }

    touch $"($h)/real-file"
    do $remove real-file
    assert equal ($"($h)/real-file" | path type) file

    ^ln -sf $"($DOTFILES)/sh/.shrc" $"($h)/live-link"
    do $remove live-link
    assert (is-link $"($h)/live-link")

    ^ln -sf /etc/hosts $"($h)/external-link"
    do $remove external-link
    assert (is-link $"($h)/external-link")

    ^ln -sf /nonexistent-outside-prefix $"($h)/dangling-external"
    do $remove dangling-external
    assert (is-link $"($h)/dangling-external")

    ^ln -sf $"($DOTFILES)/nonexistent" $"($h)/stale-link"
    do $remove stale-link
    assert not (is-link $"($h)/stale-link")
}

@test
def "clean covers every directory it lists" [] {
    let c = $in
    let h = $c.home
    let dotdirs = [
        .config/fish .config/fish/completions .config/fish/functions .config/ghostty .config/git .config/zed
        .gnupg .local/bin .local/share/bash-completion/completions .orca .ssh .vim .zsh/completions
    ] | each {|d| $"($h)/($d)" } | prepend $h
    let agentdirs = [
        .claude .claude/skills .agents/skills .claude/agents .gemini .gemini/agents
        .config/opencode/agents .pi/agent .pi/agent/prompts .codex
    ] | each {|d| $"($h)/($d)" }

    for d in $dotdirs {
        mkdir $d
        ^ln -sf $"($DOTFILES)/nonexistent" $"($d)/stale"
        ^ln -sf /nonexistent-outside-prefix $"($d)/dangling-external"
    }
    for d in $agentdirs {
        mkdir $d
        ^ln -sf $"($DOTFILES)/agents/nonexistent" $"($d)/stale"
        ^ln -sf /nonexistent-outside-prefix $"($d)/dangling-external"
    }

    let r = zsh $c '_clean'
    assert equal $r.status 0
    assert str contains $r.output removed

    for d in ($dotdirs | append $agentdirs) {
        assert not (is-link $"($d)/stale") $"stale link survived in ($d)"
        assert (is-link $"($d)/dangling-external") $"external link removed in ($d)"
    }
}

@test
def "clean protects real files and unrelated symlinks" [] {
    let c = $in
    let h = $c.home
    zsh-ok $c '_link'

    touch $"($h)/.ssh/id_rsa"
    ^ln -sf /etc/hosts $"($h)/.ssh/external_link"
    ^ln -sf $"($DOTFILES)/nonexistent" $"($h)/.ssh/stale_link"

    zsh-ok $c '_clean'

    assert equal ($"($h)/.ssh/id_rsa" | path type) file
    assert-link $"($h)/.ssh/external_link" /etc/hosts
    assert not (is-link $"($h)/.ssh/stale_link")
}

@test
def "handling paths with spaces" [] {
    let c = $in
    let repo = $"($c.home)/path with spaces"
    mkdir $"($repo)/sh" $"($repo)/agents/claude" $"($repo)/agents/codex"
    touch $"($repo)/sh/.shrc" $"($repo)/agents/codex/config.toml"
    "{}\n" | save $"($repo)/agents/claude/settings.jsonc"

    zsh-ok $c r#'DIR="$FAKE_HOME/path with spaces"; _link'#

    assert-link $"($c.home)/.bash_profile" $"($repo)/sh/.shrc"
}

@test
def "getpath resolution priority" [] {
    let r = exec $in [zsh '-c' r#'
        set -e
        source "$FAKE_HOME/setup.zsh"
        git() {
            if [[ "$*" == 'config --global get.path' ]]; then echo '/from/git/config'; return 0; fi
            command git "$@"
        }
        [[ "$(_resolve_getpath)" == '/from/git/config' ]]
        GETPATH='~/from/env'
        [[ "$(_resolve_getpath)" == '~/from/env' ]]
        unset GETPATH
        git() { return 1; }
        [[ "$(_resolve_getpath)" == '~/src' ]]
    '#]
    assert equal $r.status 0
}

@test
def "init symlink target is absolute when getpath contains a literal tilde" [] {
    let c = $in
    zsh-ok $c r#'
        GETPATH='~/src'
        git() { :; }
        _init
    '#
    assert-link $"($c.home)/.local/bin/dot" $"($c.home)/src/github.com/arbourd/dotfiles/dot"
}

@test
def "dot with no arguments exits 1 with error and usage on stderr" [] {
    let r = exec $in [zsh '-c' r#'cd "$DOTFILES" && ./dot 2>&1 >/dev/null'#]
    assert equal $r.status 1
    assert str contains $r.output "error: command required"
    assert str contains $r.output "Usage: dot [-v|--verbose] [COMMAND]"
}

@test
def "dot with unknown command exits 1 with error and usage on stderr" [] {
    let r = exec $in [zsh '-c' r#'cd "$DOTFILES" && ./dot unknown 2>&1 >/dev/null'#]
    assert equal $r.status 1
    assert str contains $r.output 'error: unknown command: "unknown"'
    assert str contains $r.output "Usage: dot [-v|--verbose] [COMMAND]"
}

# orca-db creates a minimal Orca db, stubs pgrep so Orca looks closed, and returns the db path.
def orca-db [ctx: record]: nothing -> string {
    let db = $"($ctx.home)/Library/Application Support/orca/profiles/local-default/profile-state.db"
    mkdir ($db | path dirname)
    ^sqlite3 $db r#'CREATE TABLE profile_state_documents (domain TEXT PRIMARY KEY, payload TEXT, content_hash TEXT);
        INSERT INTO profile_state_documents VALUES ('settings', '{"terminalScopeHistoryByWorktree":true,"other":1}', 'stale');'#
    stub $ctx pgrep 'exit 1'
    $db
}

# orca-get selects a column, or a json path in the payload, from the settings row.
def orca-get [db: string, expr: string]: nothing -> string {
    ^sqlite3 $db $"SELECT ($expr) FROM profile_state_documents WHERE domain='settings'"
}

def orca-key [db: string, key: string]: nothing -> string {
    orca-get $db $"json_extract\(payload, '$.($key)')"
}

@test
def "_merge_orca_settings applies values and updates content_hash" [] {
    let c = $in
    let db = orca-db $c

    zsh-ok $c r#'PATH="$FAKE_HOME/bin:$PATH"; _merge_orca_settings'#

    assert equal (orca-key $db terminalScopeHistoryByWorktree) "0"
    assert equal (orca-key $db other) "1"

    let payload = orca-get $db payload
    let hash = orca-get $db content_hash
    assert equal ($payload | ^shasum -a 256 | split row ' ' | first) $hash
}

@test
def "_merge_rex_settings skips when Rex has no preferences" [] {
    let c = $in
    stub $c defaults "exit 1\n"

    let r = zsh $c r#'PATH="$FAKE_HOME/bin:$PATH"; _merge_rex_settings'#
    assert equal $r.status 0
    assert str contains $r.output "launch Rex once"
}

@test
def "_merge_orca_settings handles a quote in the dotfiles path" [] {
    let c = $in
    let db = orca-db $c
    let quoted = $"($c.home)/it's dotfiles"
    mkdir $"($quoted)/orca"
    cp $"($DOTFILES)/orca/settings.jsonc" $"($quoted)/orca/"

    zsh-ok $c r#'PATH="$FAKE_HOME/bin:$PATH"; DIR="$FAKE_HOME/it's dotfiles"; _merge_orca_settings'#

    assert equal (orca-key $db terminalScopeHistoryByWorktree) "0"
}

@test
def "_merge_orca_settings fails and leaves the db untouched when settings.jsonc is missing" [] {
    let c = $in
    let db = orca-db $c
    mkdir $"($c.home)/repo-mock"

    let r = zsh $c r#'PATH="$FAKE_HOME/bin:$PATH"; DIR="$FAKE_HOME/repo-mock"; _merge_orca_settings 2>&1'#
    assert equal $r.status 1
    assert str contains $r.output "produced no payload"
    assert equal (orca-get $db content_hash) stale
    assert equal (orca-key $db other) "1"
}

@test
def "_merge_orca_settings skips when Orca is running" [] {
    let c = $in
    let db = orca-db $c
    stub $c pgrep "exit 0\n"

    let r = zsh $c r#'PATH="$FAKE_HOME/bin:$PATH"; _merge_orca_settings'#
    assert equal $r.status 0
    assert str contains $r.output skipped
    assert equal (orca-get $db content_hash) stale
}

@test
def "_merge_orca_settings skips when run inside Orca" [] {
    let c = $in
    let db = orca-db $c

    let r = zsh $c r#'PATH="$FAKE_HOME/bin:$PATH"; TERM_PROGRAM=Orca; _merge_orca_settings'#
    assert equal $r.status 0
    assert str contains $r.output "outside Orca"
    assert equal (orca-get $db content_hash) stale
}

@test
def "_merge_orca_settings skips when db is missing" [] {
    let c = $in
    let r = zsh $c '_merge_orca_settings'
    assert equal $r.status 0
    assert str contains $r.output skipped
    assert not ($"($c.home)/Library" | path exists)
}

@test
def "_merge_orca_settings deletes top-level and nested keys the repo sets to null" [] {
    let c = $in
    let db = orca-db $c
    mkdir $"($c.home)/repo-mock/orca"
    "{\"gone\": null, \"nested\": {\"gone\": null, \"set\": 2}, \"absent\": {\"gone\": null, \"set\": 4}}\n" | save $"($c.home)/repo-mock/orca/settings.jsonc"
    ^sqlite3 $db r#'UPDATE profile_state_documents SET payload = '{"gone":{"x":1},"nested":{"gone":1,"keep":3},"other":1}' WHERE domain='settings''#

    let r = zsh $c r#'PATH="$FAKE_HOME/bin:$PATH"; DIR="$FAKE_HOME/repo-mock"; _merge_orca_settings'#
    assert equal $r.status 0
    assert str contains $r.output merged

    let payload = orca-get $db payload | ^jq -cS .
    assert equal $payload '{"absent":{"set":4},"nested":{"keep":3,"set":2},"other":1}'
}

@test
def ".claude/skills links to the repo skills" [] {
    assert equal ($"($DOTFILES)/.claude/skills/orca-settings/SKILL.md" | path type) file
}

@test
def "orca-settings defaults.js prints defaults from a given dir and leaves it in place" [] {
    let c = $in
    mkdir $"($c.home)/asar/out/shared/orca-profiles"
    "exports.getDefaultSettings = () => ({ theme: 'system' });\n" | save $"($c.home)/asar/out/shared/orca-profiles/constants.js"

    let r = exec $c [bun $"($DOTFILES)/.agents/skills/orca-settings/scripts/defaults.js" $"($c.home)/asar"]
    assert equal $r.status 0
    assert equal ($r.output | from json).theme system
    assert equal ($"($c.home)/asar/out/shared/orca-profiles/constants.js" | path type) file
}

@test
def "gum is used on a tty" [] {
    let c = $in
    stub $c gum "echo gum-was-called\n"

    let r = zsh $c --tty r#'PATH="$FAKE_HOME/bin:$PATH"; _spin title true'#
    assert equal $r.status 0
    assert str contains $r.output gum-was-called
}

@test
def "_spin propagates gum failure" [] {
    let c = $in
    stub $c gum "exit 1\n"

    let r = zsh $c --tty r#'PATH="$FAKE_HOME/bin:$PATH"; _spin title false'#
    assert not equal $r.status 0
    assert not ($r.output =~ '(?s)ok .*title')
}

@test
def "_spin returns failure to a caller that tests it, with and without gum" [] {
    let c = $in
    stub $c gum "exit 1\n"

    # errexit is off on the left of ||, so _spin must return the failure itself
    let script = r#'PATH="$FAKE_HOME/bin:$PATH"; _spin title false || echo caught'#
    for r in [(zsh $c --tty $script) (zsh $c $script)] {
        assert str contains $r.output caught
        assert not ($r.output =~ '(?s)ok .*title')
    }
}

@test
def "NO_COLOR disables styling even on a tty with gum installed" [] {
    let c = $in
    stub $c gum "echo gum-was-called\n"

    let r = zsh $c --tty r#'PATH="$FAKE_HOME/bin:$PATH"; NO_COLOR=1; _spin title true'#
    assert equal $r.status 0
    assert str contains $r.output "ok       title"
    assert not ($r.output | str contains gum-was-called)
    assert not ($r.output | str contains "\e[")
}

@test
def "_spin falls back to running the command without gum" [] {
    let r = zsh $in '_spin title echo ran'
    assert equal $r.status 0
    assert str contains $r.output title
    assert str contains $r.output ran
}

@test
def "_spin propagates command failure" [] {
    assert not equal (zsh $in '_spin title false').status 0
}

@test
def "_spin bypasses gum with --verbose" [] {
    let c = $in
    stub $c gum "echo gum-was-called\n"

    let r = zsh $c r#'PATH="$FAKE_HOME/bin:$PATH"; _has_gum() { true; }; VERBOSE=1; _spin title echo ran'#
    assert str contains $r.output ran
    assert not ($r.output | str contains gum-was-called)
}

@test
def "dot accepts -v and --verbose before or after the command" [] {
    let c = $in
    let sha = head-sha
    for args in [[-v version] [version -v] [--verbose version] [version --verbose]] {
        let r = exec $c --cwd $DOTFILES [./dot ...$args]
        assert equal $r.status 0
        assert equal $r.output $sha
    }
}

@test
def "install fisher restores fish_plugins from the dotfiles repo, not the cwd" [] {
    let c = $in
    let h = $c.home
    let repo = $"($h)/repo"
    mkdir $"($h)/cwd" $"($repo)/sh"
    "jorgebucaran/fisher@1.2.3\n" | save $"($repo)/sh/fish_plugins"
    ^git init -q $repo
    ^git -C $repo add sh/fish_plugins
    ^git -C $repo -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m init
    "modified\n" | save -f $"($repo)/sh/fish_plugins"

    stub $c brew ""
    stub $c curl ""
    stub $c fish $"echo \"$2\" >> \"($h)/fish_args\"\n"
    mkdir $"($h)/.config/fish"
    ^ln -s $"($repo)/sh/fish_plugins" $"($h)/.config/fish/fish_plugins"

    let r = zsh $c r#'DIR="$FAKE_HOME/repo"; PATH="$FAKE_HOME/bin:$PATH"; cd "$FAKE_HOME/cwd"; _install_fisher'#
    assert equal $r.status 0
    assert equal (open --raw $"($repo)/sh/fish_plugins") "jorgebucaran/fisher@1.2.3\n"
    # uses the pinned fisher and never runs `fisher install`
    let args = open --raw $"($h)/fish_args"
    assert str contains $args "jorgebucaran/fisher/1.2.3/functions/fisher.fish | source && fisher update"
    assert not ($args | str contains "fisher install")
}

@test
def "install fisher and install vim fail before dot link" [] {
    let c = $in
    for cmd in [brew curl fish vim] { stub $c $cmd "" }

    let r = zsh $c r#'PATH="$FAKE_HOME/bin:$PATH"; _install_fisher'#
    assert not equal $r.status 0
    assert str contains $r.output "run 'dot link' first"

    let r = zsh $c r#'PATH="$FAKE_HOME/bin:$PATH"; _install_vim'#
    assert not equal $r.status 0
    assert str contains $r.output "run 'dot link' first"
}

@test
def "_repo_url prints nothing without an origin remote" [] {
    let c = $in
    ^git init -q $"($c.home)/repo"
    let r = zsh $c r#'DIR="$FAKE_HOME/repo"; _repo_url'#
    assert equal $r.status 0
    assert equal $r.output ''
}

@test
def "command lists stay in sync across dot, completions, and ci" [] {
    let c = $in
    let commands = (exec $c --cwd $DOTFILES [./dot help]).output | lines
        | between '^Commands:' --stop '^Options:' | each { field 0 } | sort
    assert ($commands | is-not-empty)

    let dispatch = open --raw $"($DOTFILES)/dot" | lines
        | parse -r '^    (?<c>[a-z-]+)\)' | get c | sort
    assert equal $dispatch $commands

    let fish = open --raw $"($DOTFILES)/sh/completions/dot.fish" | lines
        | parse -r '^set -l commands (?<c>.*)$' | get c | split row ' ' | sort
    assert equal $fish $commands

    let bash = open --raw $"($DOTFILES)/sh/completions/dot.bash" | lines
        | parse -r '.*compgen -W "(?<c>[^"]*)".*' | get c | split row ' ' | sort
    assert equal $bash $commands

    let zshc = open --raw $"($DOTFILES)/sh/completions/_dot" | lines
        | parse -r "^ *'(?<c>[a-z-]*):" | get c | sort
    assert equal $zshc $commands

    let ci = open --raw $"($DOTFILES)/.github/workflows/ci.yml" | lines
        | between 'command:' --stop 'steps:' | where ($it | str trim) != '' | each { field 1 } | uniq | sort
    assert equal $ci $commands
}

@test
def "install and merge targets stay in sync across dot, completions, and ci" [] {
    let c = $in
    let ci = open --raw $"($DOTFILES)/.github/workflows/ci.yml" | lines
    let targets_of = {|cmd|
        (exec $c --cwd $DOTFILES [./dot $cmd '--help']).output | lines
            | between '^Targets:' | each { field 0 } | where $it != '' | sort
    }

    for cmd in [install merge] {
        let targets = do $targets_of $cmd
        assert ($targets | is-not-empty)

        let fish = open --raw $"($DOTFILES)/sh/completions/dot.fish" | lines
            | parse -r $".*__fish_seen_subcommand_from ($cmd); and not __fish_seen_subcommand_from \(?<t>[a-z]*\)\".*"
            | get t | sort
        assert equal $fish $targets

        let bash = open --raw $"($DOTFILES)/sh/completions/dot.bash" | lines
            | parse -r $".*($cmd)\\) COMPREPLY=.*compgen -W '\(?<t>[^']*\)'.*" | get t | split row ' ' | sort
        assert equal $bash $targets

        let zshc = open --raw $"($DOTFILES)/sh/completions/_dot" | lines
            | parse -r $"^ *($cmd)\\) _values 'target' \(?<rest>.*\)$" | get rest
            | parse -r "'(?<t>[a-z]*)\\[" | get t | sort
        assert equal $zshc $targets

        # every target has a handler in dot's own case
        for target in $targets {
            assert (steps $c $cmd $target | is-not-empty) $"no handler for ($cmd) ($target)"
        }
    }

    # ci runs each install target separately, and merge as one task
    let installs = do $targets_of install | each {|t| $"install ($t)" }
    let ci_installs = $ci | between 'command:' --stop 'steps:'
        | where ($it | field 1) == install | each {|l| $"($l | field 1) ($l | field 2)" } | sort
    assert equal $ci_installs $installs
    assert ('          - merge' in $ci)
}

@test
def "dot --help prints usage for commands and targets, and rejects unknown targets" [] {
    let c = $in
    let dot = $"($DOTFILES)/dot"

    let r = exec $c [$dot install '--help']
    assert equal $r.status 0
    assert str contains $r.output "Usage: dot install [TARGET]"
    assert ($r.output =~ '(?s)brew.*defaults.*fisher.*vim')

    let r = exec $c [$dot merge claude '-h']
    assert equal $r.status 0
    assert str contains $r.output "Usage: dot merge claude"

    # repeating the flag, or combining it with `help`, still shows the command's usage
    let r = exec $c [$dot help install '--help']
    assert equal $r.status 0
    assert str contains $r.output "Usage: dot install [TARGET]"

    let r = exec $c [$dot install '-h' '--help']
    assert equal $r.status 0
    assert str contains $r.output "Usage: dot install [TARGET]"

    let r = exec $c [$dot help '']
    assert equal $r.status 1
    assert str contains $r.output 'unknown command: ""'

    let r = exec $c [$dot '--help']
    assert equal $r.status 0
    assert str contains $r.output "Usage: dot [-v|--verbose] [COMMAND]"

    let r = exec $c [$dot install nope '--help']
    assert equal $r.status 1
    assert str contains $r.output 'unknown install target: "nope"'
}

@test
def "dot rejects unknown and empty install/merge targets, and unknown commands with --help" [] {
    let c = $in
    let dot = $"($DOTFILES)/dot"

    let r = exec $c [$dot install nope]
    assert equal $r.status 1
    assert str contains $r.output 'unknown install target: "nope"'

    # an empty target is unknown, not run-all
    let r = exec $c [$dot install '']
    assert equal $r.status 1
    assert str contains $r.output 'unknown install target: ""'

    let r = exec $c [$dot merge '']
    assert equal $r.status 1
    assert str contains $r.output 'unknown merge target: ""'

    let r = exec $c [$dot bogus '--help']
    assert equal $r.status 1
    assert str contains $r.output 'unknown command: "bogus"'

    let r = exec $c [$dot help install]
    assert equal $r.status 0
    assert str contains $r.output "Usage: dot install [TARGET]"
}

# dot-stubbed runs dot's real dispatch with every install and merge step replaced by an echo.
def dot-stubbed [ctx: record, ...args: string]: nothing -> record {
    let copy = $"($ctx.home)/dot-stubbed"
    let src = open --raw $"($DOTFILES)/dot" | lines
    let at = $src | enumerate | where item =~ '^# Only dispatch when executed' | first | get index
    let fns = [
        _install_brew _install_defaults _install_fisher _install_vim
        _merge_claude_settings _update_claude_marketplaces _merge_codex_config _merge_orca_settings _merge_rex_settings
    ]
    let stubs = $fns | each {|fn| $"($fn)\() { echo ($fn | str substring 1..); }" }
    $src | first $at | append $stubs | append ($src | skip $at) | str join "\n" | save -f $copy

    let r = with-env {HOME: $ctx.home} { ^zsh $copy ...$args o+e>| complete }
    {status: $r.exit_code, output: ($r.stdout | str replace -r '\n+$' '')}
}

# steps lists the stubbed steps that ran.
def steps [ctx: record, ...args: string]: nothing -> list<string> {
    (dot-stubbed $ctx ...$args).output | lines | where $it =~ '^(install|merge|update)_'
}

@test
def "dot install and merge run every step without a target, and the given ones with targets" [] {
    let c = $in
    assert equal (steps $c install) [install_brew install_defaults install_fisher install_vim]
    assert equal (steps $c install vim) [install_vim]
    assert equal (steps $c install vim brew) [install_vim install_brew]

    assert equal (steps $c merge) [merge_claude_settings update_claude_marketplaces merge_codex_config merge_orca_settings merge_rex_settings]
    assert equal (steps $c merge codex) [merge_codex_config]
    assert equal (steps $c merge orca claude) [merge_orca_settings merge_claude_settings update_claude_marketplaces]

    # an unknown target fails before any step runs
    let r = dot-stubbed $c install brew nope
    assert equal $r.status 1
    assert str contains $r.output 'unknown install target: "nope"'
    assert equal (steps $c install brew nope) []

    let r = dot-stubbed $c merge codex nope
    assert equal $r.status 1
    assert equal (steps $c merge codex nope) []
}

@test
def "_install_brew bundles the Brewfile without a lockfile" [] {
    let c = $in
    stub $c brew "echo \"brew-called $HOMEBREW_BUNDLE_NO_LOCK $*\"\n"
    stub $c curl ""

    let r = zsh $c r#'PATH="$FAKE_HOME/bin:$PATH"; _install_brew'#
    assert equal $r.status 0
    assert str contains $r.output $"brew-called 1 bundle --file ($DOTFILES)/Brewfile"
}

@test
def "_install_vim hides vim output on success and shows it on failure" [] {
    let c = $in
    stub $c curl ""
    stub $c vim "echo vim-output\n"
    mkdir $"($c.home)/.vim"
    touch $"($c.home)/.vim/vimrc"

    let r = zsh $c r#'PATH="$FAKE_HOME/bin:$PATH"; _install_vim'#
    assert equal $r.status 0
    assert not ($r.output | str contains vim-output)

    let r = zsh $c r#'PATH="$FAKE_HOME/bin:$PATH"; VERBOSE=1; _install_vim'#
    assert equal $r.status 0
    assert str contains $r.output vim-output

    stub $c vim "echo vim-boom\nexit 1\n"
    let r = zsh $c r#'PATH="$FAKE_HOME/bin:$PATH"; _install_vim'#
    assert not equal $r.status 0
    assert str contains $r.output vim-boom
}

@test
def "vendored skills are pinned and present in agents/skills" [] {
    let skills = open $"($DOTFILES)/agents/skills.json" | get skills
    # A commit pin is immutable; a branch or tag in its place would drift silently.
    let unpinned = $skills | values | get source | where not ($it =~ '@[0-9a-f]{40}$')
    assert equal $unpinned []

    # Skills absent from skills.json are local and maintained here.
    for name in ($skills | columns) {
        assert ($"($DOTFILES)/agents/skills/($name)/SKILL.md" | path exists) $"($name) not vendored"
    }
}
