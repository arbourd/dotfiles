#!/usr/bin/env zsh

data=$(cat)
j() { print -r -- "$data" | jq -r "${1} // empty" }

blue=$'\033[38;2;0;153;255m'
orange=$'\033[38;2;255;176;85m'
green=$'\033[38;2;0;160;0m'
cyan=$'\033[38;2;46;149;153m'
red=$'\033[38;2;255;85;85m'
yellow=$'\033[38;2;230;200;0m'
purple=$'\033[38;2;167;139;250m'
white=$'\033[38;2;220;220;220m'
dim=$'\033[2m'
RST=$'\033[0m'

color_pct() {
    local pct=$1
    if   (( pct >= 90 )); then printf '%s' "$red"
    elif (( pct >= 70 )); then printf '%s' "$orange"
    elif (( pct >= 50 )); then printf '%s' "$yellow"
    else                       printf '%s' "$green"
    fi
}

# Model
model=$(j '.model.display_name')

# CWD@Branch +added/-deleted
cwd=$(j '.cwd')
folder=${cwd:t}
branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
if [[ -n "$branch" ]]; then
    read added deleted <<< $(git -C "$cwd" status --porcelain 2>/dev/null | awk '
        /^[ MARC?!]D|^D/{d++; next} {a++}
        END{print a+0, d+0}
    ')
    cwd_seg="${folder}@${branch}"
    (( added > 0 || deleted > 0 )) && cwd_seg+=" ${green}+${added}${RST}/${red}-${deleted}${RST}"
else
    cwd_seg="$folder"
fi

# Tokens: used/total (%)
fmt_tokens='if . >= 1000000000 then (. / 1000000000 | round | tostring) + "B" elif . >= 1000000 then (. / 1000000 | round | tostring) + "M" else (. / 1000 | round | tostring) + "k" end'
used_k=$(j "(.context_window.total_input_tokens | $fmt_tokens)")
total_k=$(j "(.context_window.context_window_size  | $fmt_tokens)")
tok_pct=$(j '.context_window.used_percentage | floor')
tokens="${used_k}/${total_k} ($(color_pct $tok_pct)${tok_pct}%${RST})"

# Effort
effort=$(j '.effort.level')

# Parse a UTC ISO 8601 timestamp and format in local timezone
fmt_time() {
    local raw=$1 epoch
    [[ -z "$raw" ]] && return
    epoch=$(TZ=UTC date -jf "%Y-%m-%dT%H:%M:%SZ" "$raw" "+%s" 2>/dev/null) || return
    date -r "$epoch" "+%H:%M" 2>/dev/null
}

# 5h rate limit
five_pct=$(j '.rate_limits.five_hour.used_percentage | floor')
five_reset=$(fmt_time "$(j '.rate_limits.five_hour.resets_at')")

# 7d rate limit
seven_pct=$(j '.rate_limits.seven_day.used_percentage | floor')
seven_reset=$(fmt_time "$(j '.rate_limits.seven_day.resets_at')")

# Cost
cost=$(j '.cost.total_cost_usd | if type == "number" then "$" + (. * 100 | round / 100 | tostring) else empty end')

# Assemble segments, skipping empty ones
segs=()
[[ -n "$model"    ]] && segs+=("$model")
[[ -n "$cwd_seg"  ]] && segs+=("$cwd_seg")
[[ -n "$used_k"   ]] && segs+=("$tokens")
if [[ -n "$effort" ]]; then
    case "$effort" in
        low)   effort_color="$green"  ;;
        med)   effort_color="$yellow" ;;
        high)  effort_color="$orange" ;;
        xhigh) effort_color="$red"    ;;
        max)   effort_color="$purple" ;;
        *)     effort_color="$white"  ;;
    esac
    segs+=("${effort_color}${effort}${RST}")
fi
[[ -n "$five_pct" ]] && segs+=("5h: $(color_pct $five_pct)${five_pct}%${RST}${five_reset:+ @ }${five_reset}")
[[ -n "$seven_pct" ]] && segs+=("7d: $(color_pct $seven_pct)${seven_pct}%${RST}${seven_reset:+ @ }${seven_reset}")
[[ -n "$cost"      ]] && segs+=("$cost")

print -r -- "${(j: | :)segs}"
