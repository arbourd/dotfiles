package cli

import (
	"context"
	"fmt"
	"slices"
	"strings"

	"github.com/arbourd/dotfiles/internal/install"
	"github.com/arbourd/dotfiles/internal/merge"
	"github.com/arbourd/dotfiles/internal/ui"
)

// Step is the work performed by an install or merge target.
type Step func(ctx context.Context, u *ui.UI) error

// Target is a named install or merge step.
type Target struct {
	Name string
	Desc string
	Run  Step
}

// Targets lists a command's targets in their default run order.
type Targets struct {
	Install []Target
	Merge   []Target
}

// DefaultTargets returns the real install and merge steps.
func DefaultTargets() Targets {
	return Targets{
		Install: []Target{
			{"brew", "installs homebrew packages", install.Brew},
			{"defaults", "installs macos defaults", install.Defaults},
			{"fisher", "installs fisher packages", install.Fisher},
			{"vim", "installs vim packages", install.Vim},
		},
		Merge: []Target{
			{"claude", "merges agents/claude/settings.jsonc into ~/.claude/settings.json and config.jsonc into ~/.claude.json, then updates marketplaces", merge.Claude},
			{"codex", "merges agents/codex/config.toml into ~/.codex/config.toml", merge.Codex},
			{"orca", "merges orca/settings.jsonc into Orca's profile db", merge.Orca},
			{"rex", "writes pinned Rex.app preferences with defaults write", merge.Rex},
		},
	}
}

// selectTargets returns the named targets in order, or all targets by default.
// It fails on an unknown name before anything runs.
func selectTargets(cmd string, ts []Target, args []string) ([]Target, error) {
	if len(args) == 0 {
		return ts, nil
	}
	out := make([]Target, 0, len(args))
	for _, a := range args {
		i := slices.IndexFunc(ts, func(t Target) bool { return t.Name == a })
		if i < 0 {
			return nil, usageErrorf("error: unknown %s target: %q", cmd, a)
		}
		out = append(out, ts[i])
	}
	return out, nil
}

func targetHelp(ts []Target) string {
	width := 0
	for _, t := range ts {
		width = max(width, len(t.Name))
	}
	var b strings.Builder
	b.WriteString("Targets:\n")
	for _, t := range ts {
		fmt.Fprintf(&b, "  %-*s  %s\n", width, t.Name, t.Desc)
	}
	return strings.TrimSuffix(b.String(), "\n")
}
