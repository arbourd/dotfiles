// Package paths resolves the dotfiles directory and provides filesystem helpers.
package paths

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/arbourd/dotfiles/internal/env"
	"github.com/arbourd/dotfiles/internal/ui"
)

// DotfilesPath returns the directory dot manages: $DOT_DIR if set, otherwise
// the default path. The result is absolute and cleaned.
func DotfilesPath(e *env.Env) string {
	if e.DotDir != "" {
		return abs(e.DotDir)
	}
	return DefaultPath(e)
}

// DefaultPath returns where `init` clones the dotfiles: $XDG_DATA_HOME/dotfiles,
// or ~/.local/share/dotfiles when XDG_DATA_HOME is unset.
func DefaultPath(e *env.Env) string {
	if e.XDGDataHome != "" {
		return abs(filepath.Join(e.XDGDataHome, "dotfiles"))
	}
	return abs(filepath.Join(e.Home, ".local", "share", "dotfiles"))
}

func abs(p string) string {
	if a, err := filepath.Abs(p); err == nil {
		return a
	}
	return filepath.Clean(p)
}

// WarnLocation warns when $DOT_DIR points to a checkout other than the managed one.
func WarnLocation(u *ui.UI, e *env.Env) {
	if e.DotDir == "" {
		return
	}
	dir, def := DotfilesPath(e), DefaultPath(e)
	if sameDir(dir, def) {
		return
	}
	u.Status(ui.Warn, fmt.Sprintf("running from %s, not %s", dir, def))
}

// sameDir reports whether a and b are the same path, comparing symlink-resolved
// paths when both exist.
func sameDir(a, b string) bool {
	if a == b {
		return true
	}
	ra, errA := filepath.EvalSymlinks(a)
	rb, errB := filepath.EvalSymlinks(b)
	return errA == nil && errB == nil && ra == rb
}

// Ensure creates path and its parents; a trailing slash makes it a directory.
// Existing files are untouched, and a non-zero mode is applied to path.
func Ensure(path string, mode fs.FileMode) error {
	if strings.HasSuffix(path, "/") {
		if err := os.MkdirAll(path, 0o755); err != nil {
			return fmt.Errorf("ensure %s: %w", path, err)
		}
	} else {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			return fmt.Errorf("ensure %s: %w", path, err)
		}
		// No O_TRUNC: an existing file keeps its contents.
		f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY, 0o666)
		if err != nil {
			return fmt.Errorf("ensure %s: %w", path, err)
		}
		if err := f.Close(); err != nil {
			return fmt.Errorf("ensure %s: %w", path, err)
		}
	}
	if mode != 0 {
		if err := os.Chmod(path, mode); err != nil {
			return fmt.Errorf("ensure %s: %w", path, err)
		}
	}
	return nil
}

// Symlink links src at link, replacing any existing link, and reports it.
// When link is a directory, or a symlink to one, src is linked inside it under
// its own name, as ln -sf does.
func Symlink(u *ui.UI, src, link string) error {
	// Stat follows symlinks, so a linked directory such as ~/.claude/skills is kept.
	if fi, err := os.Stat(link); err == nil && fi.IsDir() {
		link = filepath.Join(link, filepath.Base(src))
	}
	if err := os.Remove(link); err != nil && !errors.Is(err, fs.ErrNotExist) {
		return fmt.Errorf("symlink %s: %w", link, err)
	}
	if err := os.Symlink(src, link); err != nil {
		return fmt.Errorf("symlink %s: %w", link, err)
	}
	u.Status(ui.Linked, link+" → "+src)
	return nil
}

// RemoveStaleLink removes link only when it points to a missing target within prefix.
func RemoveStaleLink(u *ui.UI, link, prefix string) (bool, error) {
	if fi, err := os.Lstat(link); err != nil || fi.Mode()&fs.ModeSymlink == 0 {
		return false, nil
	}
	target, err := os.Readlink(link)
	if err != nil {
		return false, fmt.Errorf("remove stale link %s: %w", link, err)
	}
	if !strings.HasPrefix(target, prefix) {
		return false, nil
	}
	if _, err := os.Stat(target); err == nil {
		return false, nil
	}
	if err := os.Remove(link); err != nil {
		return false, fmt.Errorf("remove stale link %s: %w", link, err)
	}
	u.Status(ui.Removed, link)
	return true, nil
}

// CleanDir removes stale symlinks into prefix, including hidden entries, and skips missing dirs.
func CleanDir(u *ui.UI, prefix string, dirs ...string) error {
	removed := false
	for _, dir := range dirs {
		entries, err := os.ReadDir(dir)
		if errors.Is(err, fs.ErrNotExist) {
			continue
		}
		if err != nil {
			return fmt.Errorf("clean %s: %w", dir, err)
		}
		for _, e := range entries {
			ok, err := RemoveStaleLink(u, filepath.Join(dir, e.Name()), prefix)
			if err != nil {
				return err
			}
			removed = removed || ok
		}
	}
	if !removed {
		u.Status(ui.OK, "none found")
	}
	return nil
}
