package link

import (
	"os"
	"path/filepath"
	"strings"

	"github.com/arbourd/dotfiles/internal/paths"
	"github.com/arbourd/dotfiles/internal/ui"
)

// Paths used to link agent files, relative to HOME.
var (
	personaDirs  = []string{".claude/agents", ".gemini/agents", ".config/opencode/agents", ".pi/agent/prompts"}
	skillDirs    = []string{".claude/skills", ".agents/skills"}
	instructions = []string{".claude/AGENTS.md", ".gemini/GEMINI.md", ".codex/AGENTS.md", ".pi/agent/AGENTS.md"}
)

func linkAgents(u *ui.UI) error {
	home := func(p string) string { return filepath.Join(u.Env.Home, p) }
	dir := func(p string) string { return home(p) + "/" }
	agents := filepath.Join(u.Dir, "agents")

	if err := paths.Ensure(dir(".claude"), 0); err != nil {
		return err
	}
	claude, err := glob(filepath.Join(agents, "claude"), func(os.DirEntry) bool { return true })
	if err != nil {
		return err
	}
	for _, c := range claude {
		// These files are merged by dot.
		if b := filepath.Base(c); b == "settings.jsonc" || b == "config.jsonc" {
			continue
		}
		if err := paths.Symlink(u, c, home(".claude")); err != nil {
			return err
		}
	}

	for _, d := range append(append([]string{}, personaDirs...), ".claude/skills", ".agents/skills", ".codex") {
		if err := paths.Ensure(dir(d), 0); err != nil {
			return err
		}
	}

	personas, err := glob(filepath.Join(agents, "personas"), func(e os.DirEntry) bool {
		return strings.HasSuffix(e.Name(), ".md")
	})
	if err != nil {
		return err
	}
	for _, p := range personas {
		for _, d := range personaDirs {
			if err := paths.Symlink(u, p, home(d)); err != nil {
				return err
			}
		}
	}

	skills, err := glob(filepath.Join(agents, "skills"), func(e os.DirEntry) bool {
		// Stat follows symlinks, like zsh's (/) qualifier.
		fi, err := os.Stat(filepath.Join(agents, "skills", e.Name()))
		return err == nil && fi.IsDir()
	})
	if err != nil {
		return err
	}
	for _, s := range skills {
		for _, d := range skillDirs {
			if err := paths.Symlink(u, s, home(d)); err != nil {
				return err
			}
		}
	}

	for _, f := range instructions {
		if err := paths.Symlink(u, filepath.Join(agents, "AGENTS.md"), home(f)); err != nil {
			return err
		}
	}
	return nil
}
