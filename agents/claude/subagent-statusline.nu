#!/usr/bin/env nu

# One {"id", "content"} JSON line per subagent row in the agent panel.

const green  = "\e[38;2;0;160;0m"
const yellow = "\e[38;2;230;200;0m"
const orange = "\e[38;2;255;176;85m"
const red    = "\e[38;2;255;85;85m"
const purple = "\e[38;2;167;139;250m"
const white  = "\e[38;2;220;220;220m"
const RST    = "\e[0m"

# claude-opus-5-5[1m] -> Opus 5.5 (1M); unknown shapes pass through.
def model-name [] {
    let id = $in
    if $id == null { return null }
    let ctx = if ($id | str ends-with "[1m]") { " (1M)" } else { "" }
    let parts = $id
        | str replace -r '\[1m\]$' ''
        | str replace -r '^claude-' ''
        | str replace -r '-\d{8}$' ''
        | split row '-'
    let family = $parts | where $it !~ '^\d+$' | each { str capitalize } | str join ' '
    let version = $parts | where $it =~ '^\d+$' | str join '.'
    ([$family $version] | compact --empty | str join ' ') + $ctx
}

def pct-color [] {
    let p = $in
    if $p >= 90 { $red } else if $p >= 70 { $orange } else if $p >= 50 { $yellow } else { $green }
}

def effort-color [] {
    match $in { "low" => $green, "medium" | "med" => $yellow, "high" => $orange, "xhigh" => $red, "max" => $purple, _ => $white }
}

def tokens [] {
    let n = $in
    if $n >= 1_000_000 { $"($n / 1_000_000 | math round)M" } else { $"($n / 1000 | math round)k" }
}

def main [] {
    $in | from json | get tasks | each {|t|
        let used = $t.tokenCount? | default 0
        let window = $t.contextWindowSize? | default 0
        let effort = if $t.effort? != null { $"($t.effort | effort-color)($t.effort)($RST)" }
        let ctx = if $window > 0 {
            let pct = $used * 100 / $window | math floor
            $"($used | tokens)/($window | tokens) \(($pct | pct-color)($pct)%($RST)\)"
        }
        let label = $t.label? | default $t.description?
        {
            id: $t.id
            content: ([($t.model? | model-name) $effort $ctx $label] | compact --empty | str join " | ")
        } | to json --raw
    } | str join "\n" | print
}
