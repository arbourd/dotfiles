#!/usr/bin/env nu

const orange = "\e[38;2;255;176;85m"
const green = "\e[38;2;0;160;0m"
const red = "\e[38;2;255;85;85m"
const yellow = "\e[38;2;230;200;0m"
const purple = "\e[38;2;167;139;250m"
const white = "\e[38;2;220;220;220m"
const rst = "\e[0m"

# Floored percentage, coloured by how full it is
def pct [p] {
    let p = $p | math floor
    let color = if $p >= 90 { $red } else if $p >= 70 { $orange } else if $p >= 50 { $yellow } else { $green }
    $"($color)($p)%($rst)"
}

def fmt-tokens [n] {
    if $n >= 1_000_000 { $"($n / 1_000_000 | math round)M" } else { $"($n / 1000 | math round)k" }
}

# Unix epoch seconds as HH:MM in the local timezone
def fmt-time [epoch] {
    $epoch | math floor | into datetime --format "%s" | date to-timezone local | format date "%H:%M"
}

# Project name, as Codex does: folder of the nearest ancestor with a .git entry
# (a linked worktree's .git file counts, so it shows the worktree's folder)
def project-name [dir: string] {
    if ($dir | path join .git | path exists) { $dir | path basename } else if $dir != "/" { project-name ($dir | path dirname) }
}

def limit-seg [label: string, limit] {
    if $limit != null { $"($label): (pct $limit.used_percentage) @ (fmt-time $limit.resets_at)" }
}

def main [] {
    let data = $in | from json
    let ctx = $data.context_window
    let effort = $data.effort?.level?

    let tokens = $"(fmt-tokens $ctx.total_input_tokens)/(fmt-tokens $ctx.context_window_size)"
    let tokens = if $ctx.used_percentage != null { $"($tokens) \((pct $ctx.used_percentage)\)" } else { $tokens }

    let effort_seg = if $effort != null {
        let color = match $effort {
            "low" => $green
            "medium" => $yellow
            "high" => $orange
            "xhigh" => $red
            "max" => $purple
            _ => $white
        }
        $"($color)($effort)($rst)"
    }

    print ([
        $data.model.display_name
        (project-name $data.cwd)
        $tokens
        $effort_seg
        (limit-seg "5h" $data.rate_limits?.five_hour?)
        (limit-seg "7d" $data.rate_limits?.seven_day?)
        $"$($data.cost.total_cost_usd * 100 | math round | $in / 100 | into string)"
    ] | compact --empty | str join " | ")
}
