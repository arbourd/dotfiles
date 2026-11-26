package merge

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/arbourd/dotfiles/internal/env"
	"github.com/arbourd/dotfiles/internal/paths"
	"github.com/arbourd/dotfiles/internal/ui"
)

// Claude merges repository settings into Claude's live files and syncs plugin marketplaces.
func Claude(ctx context.Context, u *ui.UI) error {
	if err := claudeSettings(ctx, u); err != nil {
		return err
	}
	return claudeMarketplaces(ctx, u)
}

func claudeSettings(ctx context.Context, u *ui.UI) error {
	home := u.Env.Home
	if err := paths.Ensure(filepath.Join(home, ".claude")+"/", 0); err != nil {
		return err
	}

	files := []struct{ name, live string }{
		{"settings.jsonc", filepath.Join(home, ".claude", "settings.json")},
		{"config.jsonc", filepath.Join(home, ".claude.json")},
	}

	// Merge both before writing either, so a missing or invalid file leaves both untouched.
	merged := make([][]byte, len(files))
	for i, f := range files {
		out, err := mergeFile(ctx, f.live, filepath.Join(u.Dir, "agents", "claude", f.name))
		if err != nil {
			return fmt.Errorf("Error: claude merge failed (%s): %w", f.name, err)
		}
		if len(out) == 0 {
			return fmt.Errorf("Error: claude merge produced nothing (%s missing?)", f.name)
		}
		merged[i] = out
	}

	for i, f := range files {
		if err := writeReplace(f.live, append(merged[i], '\n')); err != nil {
			return err
		}
		u.Status(ui.Merged, filepath.Join(u.Dir, "agents", "claude", f.name)+" → "+f.live)
	}
	return nil
}

// mergeFile patches the repo file over the live file; a missing repo file is empty.
func mergeFile(ctx context.Context, livePath, repoPath string) ([]byte, error) {
	repo, err := os.ReadFile(repoPath)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	live, err := os.ReadFile(livePath)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return nil, err
	}
	return JSONPatch(ctx, live, repo)
}

// writeReplace atomically replaces path without following a symlink there.
func writeReplace(path string, data []byte) error {
	tmp, err := os.CreateTemp(filepath.Dir(path), "."+filepath.Base(path)+".*")
	if err != nil {
		return err
	}
	name := tmp.Name()
	if err := writeClose(tmp, data); err != nil {
		os.Remove(name)
		return err
	}
	if err := os.Rename(name, path); err != nil {
		os.Remove(name)
		return err
	}
	return nil
}

func writeClose(f *os.File, data []byte) error {
	if err := f.Chmod(0o600); err != nil {
		f.Close()
		return err
	}
	if _, err := f.Write(data); err != nil {
		f.Close()
		return err
	}
	return f.Close()
}

func claudeMarketplaces(ctx context.Context, u *ui.UI) error {
	if !env.Has(u.Env.Runner, "claude") {
		u.Status(ui.Skipped, "claude marketplaces: claude not installed")
		return nil
	}
	// Continue local merges even when marketplace updates fail.
	if err := u.SpinCmd(ctx, "claude marketplaces", env.Cmd{Name: "claude", Args: []string{"plugin", "marketplace", "update"}}); err != nil {
		u.Status(ui.Warn, "claude marketplaces: update failed")
	}
	return nil
}
