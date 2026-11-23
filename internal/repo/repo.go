// Package repo manages the dotfiles Git repository.
package repo

import (
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"

	"github.com/arbourd/dotfiles/internal/env"
	"github.com/arbourd/dotfiles/internal/paths"
	"github.com/arbourd/dotfiles/internal/ui"
)

// CloneURL is the repository Init clones.
var CloneURL = "https://github.com/arbourd/dotfiles.git"

// SparsePatterns allowlist runtime files in a managed non-cone sparse checkout.
var SparsePatterns = []string{
	"/Brewfile",
	"/.macOS",
	"/agents/",
	"!/agents/skills.json",
	"!/agents/vendor-skills",
	"/ghostty/",
	"/git/",
	"/gpg/",
	"/orca/",
	"/rex/",
	"/sh/",
	"/ssh/",
	"/vim/",
	"/zed/",
}

// Init creates a blobless sparse checkout or pulls an existing clone without changing its sparse config.
func Init(ctx context.Context, u *ui.UI) error {
	return initFrom(ctx, u, CloneURL, SparsePatterns)
}

func initFrom(ctx context.Context, u *ui.UI, url string, patterns []string) error {
	u.Log("Initializing dotfiles")

	if fi, err := os.Stat(u.Dir); err == nil && fi.IsDir() {
		u.Status(ui.OK, u.Dir+" already exists, pulling")
		args := []string{"-C", u.Dir, "pull"}
		if u.Verbose {
			args = append(args, "-v")
		}
		return u.SpinCmd(ctx, "pulling dotfiles", env.Cmd{Name: "git", Args: args})
	}

	if err := paths.Ensure(filepath.Dir(u.Dir)+"/", 0); err != nil {
		return err
	}
	clone := []string{"clone", "--filter=blob:none", "--no-checkout"}
	if u.Verbose {
		clone = append(clone, "-v")
	}
	steps := [][]string{
		append(clone, url, u.Dir),
		append([]string{"-C", u.Dir, "sparse-checkout", "set", "--no-cone"}, patterns...),
		{"-C", u.Dir, "checkout"},
	}
	// Use one spinner for the clone so success is reported once.
	return u.Spin("cloning dotfiles", func(stdout, stderr io.Writer) error {
		for _, args := range steps {
			c := env.Cmd{Name: "git", Args: args, Stdout: stdout, Stderr: stderr}
			if err := u.Env.Runner.Run(ctx, c); err != nil {
				// Remove an incomplete clone so the next init does not mistake it for a valid checkout.
				if rmErr := os.RemoveAll(u.Dir); rmErr != nil {
					return errors.Join(err, rmErr)
				}
				return err
			}
		}
		return nil
	})
}

// Update pulls the dotfiles and reports the old and new commit, refreshing sparse patterns as needed.
func Update(ctx context.Context, u *ui.UI) error {
	return update(ctx, u, SparsePatterns)
}

func update(ctx context.Context, u *ui.UI, patterns []string) error {
	before, err := Head(ctx, u)
	if err != nil {
		return err
	}
	flag := "--quiet"
	if u.Verbose {
		flag = "-v"
	}
	if err := u.SpinCmd(ctx, "pulling dotfiles", env.Cmd{Name: "git", Args: []string{"-C", u.Dir, "pull", flag}}); err != nil {
		return err
	}
	if err := reapplySparse(ctx, u, patterns); err != nil {
		return err
	}
	after, err := Head(ctx, u)
	if err != nil {
		return err
	}
	repo := URL(ctx, u)

	if before == after {
		u.Status(ui.OK, "dotfiles "+u.Hyperlink(link(repo, "/commit/"+after), after)+" (up to date)")
		return nil
	}
	u.Status(ui.Updated, "dotfiles "+u.Hyperlink(link(repo, "/compare/"+before+"..."+after), before+" → "+after))
	return nil
}

// reapplySparse updates sparse patterns without changing full clones.
func reapplySparse(ctx context.Context, u *ui.UI, patterns []string) error {
	// git config exits 1 when the key is unset, which means a full clone.
	sparse, err := git(ctx, u.Env, u.Dir, "config", "--bool", "--get", "core.sparseCheckout")
	if err != nil || sparse != "true" {
		return nil
	}
	_, err = git(ctx, u.Env, u.Dir, append([]string{"sparse-checkout", "set", "--no-cone"}, patterns...)...)
	return err
}

// link joins repo and path, or returns "" without a repo URL.
func link(repo, path string) string {
	if repo == "" {
		return ""
	}
	return repo + path
}
