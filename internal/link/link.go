// Package link manages dotfile symlinks in the home directory.
package link

import (
	"context"
	"os"
	"path/filepath"
	"strings"

	"github.com/arbourd/dotfiles/internal/paths"
	"github.com/arbourd/dotfiles/internal/ui"
)

// CleanDirs are home-relative directories scanned for stale dotfile links; "" is HOME.
var CleanDirs = []string{
	"", ".config/fish", ".config/fish/completions", ".config/fish/functions",
	".config/ghostty", ".config/git", ".config/zed", ".gnupg", ".local/bin",
	".local/share/bash-completion/completions", ".orca", ".ssh", ".vim", ".zsh/completions",
}

// CleanAgentDirs are home-relative directories scanned for stale agent links.
var CleanAgentDirs = []string{
	".claude", ".claude/skills", ".agents/skills", ".claude/agents", ".gemini",
	".gemini/agents", ".config/opencode/agents", ".pi/agent", ".pi/agent/prompts", ".codex",
}

type ensure struct {
	path string
	mode os.FileMode
}

type entry struct{ src, link string }

type step struct {
	ensure *ensure
	entry  *entry
}

func mk(path string, mode os.FileMode) step { return step{ensure: &ensure{path, mode}} }
func ln(src, link string) step              { return step{entry: &entry{src, link}} }

// The split preserves zsh's position of the fish functions glob.
var dotfileStepsA = []step{
	mk(".config/fish/private.fish", 0o600),
	ln("sh/.shrc", ".bash_profile"),
	ln("sh/.shrc", ".bashrc"),
	ln("sh/.shrc", ".zshrc"),
	ln("sh/config.fish", ".config/fish/config.fish"),
	ln("sh/fish_plugins", ".config/fish/fish_plugins"),
	mk(".config/fish/functions/", 0),
}

var dotfileStepsB = []step{
	mk(".config/fish/completions/", 0),
	ln("sh/completions/dot.fish", ".config/fish/completions/dot.fish"),
	mk(".local/share/bash-completion/completions/", 0),
	ln("sh/completions/dot.bash", ".local/share/bash-completion/completions/dot"),
	mk(".zsh/completions/", 0),
	ln("sh/completions/_dot", ".zsh/completions/_dot"),
	mk(".config/ghostty/", 0),
	ln("ghostty/config", ".config/ghostty/config"),
	mk(".config/git/private", 0o600),
	ln("git/config", ".config/git/config"),
	ln("git/gitignore", ".config/git/gitignore"),
	mk(".gnupg/", 0o700),
	ln("gpg/gpg-agent.conf", ".gnupg/gpg-agent.conf"),
	mk(".orca/", 0),
	ln("orca/keybindings.json", ".orca/keybindings.json"),
	mk(".ssh/", 0),
	ln("ssh/config", ".ssh/config"),
	mk(".vim/", 0),
	ln("vim/vimrc", ".vim/vimrc"),
	mk(".config/zed/", 0),
	ln("zed/settings.json", ".config/zed/settings.json"),
}

// Link creates dotfile and agent symlinks, then removes stale links.
func Link(ctx context.Context, u *ui.UI) error {
	u.Log("Symlinking dotfiles")
	if err := run(u, dotfileStepsA); err != nil {
		return err
	}
	// The fish functions are linked into the (now existing) functions dir.
	fns, err := glob(filepath.Join(u.Dir, "sh", "functions"), func(e os.DirEntry) bool {
		return strings.HasSuffix(e.Name(), ".fish")
	})
	if err != nil {
		return err
	}
	for _, fn := range fns {
		if err := paths.Symlink(u, fn, filepath.Join(u.Env.Home, ".config/fish/functions")); err != nil {
			return err
		}
	}
	if err := run(u, dotfileStepsB); err != nil {
		return err
	}

	u.Log("Symlinking agent dotfiles")
	if err := linkAgents(u); err != nil {
		return err
	}
	if err := Clean(ctx, u); err != nil {
		return err
	}
	u.Log("Run dot merge to merge settings")
	return nil
}

// Clean removes stale dotfile and agent symlinks.
func Clean(_ context.Context, u *ui.UI) error {
	u.Log("Cleaning stale dotfile symlinks")
	if err := paths.CleanDir(u, u.Dir+"/", homeJoin(u, CleanDirs)...); err != nil {
		return err
	}
	u.Log("Cleaning stale agent dotfile symlinks")
	return paths.CleanDir(u, u.Dir+"/agents/", homeJoin(u, CleanAgentDirs)...)
}

func homeJoin(u *ui.UI, rel []string) []string {
	out := make([]string, len(rel))
	for i, r := range rel {
		out[i] = filepath.Join(u.Env.Home, r)
	}
	return out
}

func run(u *ui.UI, steps []step) error {
	for _, s := range steps {
		if s.ensure != nil {
			p := filepath.Join(u.Env.Home, s.ensure.path)
			if strings.HasSuffix(s.ensure.path, "/") {
				p += "/"
			}
			if err := paths.Ensure(p, s.ensure.mode); err != nil {
				return err
			}
			continue
		}
		err := paths.Symlink(u, filepath.Join(u.Dir, s.entry.src), filepath.Join(u.Env.Home, s.entry.link))
		if err != nil {
			return err
		}
	}
	return nil
}

// glob returns sorted, non-hidden entries accepted by keep; a missing dir yields none.
func glob(dir string, keep func(os.DirEntry) bool) ([]string, error) {
	entries, err := os.ReadDir(dir)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var out []string
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), ".") || !keep(e) {
			continue
		}
		out = append(out, filepath.Join(dir, e.Name()))
	}
	return out, nil
}
