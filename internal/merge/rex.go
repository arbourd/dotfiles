package merge

import (
	"context"
	"path/filepath"

	"github.com/arbourd/dotfiles/internal/env"
	"github.com/arbourd/dotfiles/internal/ui"
)

const rexDomain = "com.superlogical.rex"

// Rex applies the pinned Rex.app preferences.
func Rex(ctx context.Context, u *ui.UI) error {
	if err := u.Env.Runner.Run(ctx, env.Cmd{Name: "defaults", Args: []string{"read", rexDomain}}); err != nil {
		u.Status(ui.Skipped, "rex settings: no preferences yet, launch Rex once and rerun")
		return nil
	}

	err := u.Env.Runner.Run(ctx, env.Cmd{
		Name:   filepath.Join(u.Dir, "rex", "settings.zsh"),
		Stdout: u.Env.Stdout,
		Stderr: u.Env.Stderr,
	})
	if err != nil {
		return err
	}

	u.Status(ui.Merged, "rex settings → "+rexDomain)
	return nil
}
