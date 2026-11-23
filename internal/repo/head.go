package repo

import (
	"bytes"
	"context"
	"fmt"
	"strings"

	"github.com/arbourd/dotfiles/internal/env"
	"github.com/arbourd/dotfiles/internal/ui"
)

func git(ctx context.Context, e *env.Env, dir string, args ...string) (string, error) {
	var out, errOut bytes.Buffer
	err := e.Runner.Run(ctx, env.Cmd{
		Name:   "git",
		Args:   append([]string{"-C", dir}, args...),
		Stdout: &out,
		Stderr: &errOut,
	})
	if err != nil {
		if msg := strings.TrimSpace(errOut.String()); msg != "" {
			return "", fmt.Errorf("git %s: %w: %s", args[0], err, msg)
		}
		return "", fmt.Errorf("git %s: %w", args[0], err)
	}
	return strings.TrimSpace(out.String()), nil
}

// Head returns the short commit SHA checked out in u.Dir.
func Head(ctx context.Context, u *ui.UI) (string, error) {
	return git(ctx, u.Env, u.Dir, "rev-parse", "--short", "HEAD")
}

// URL returns origin's GitHub URL, or "" if origin is missing or not on GitHub.
func URL(ctx context.Context, u *ui.UI) string {
	url, err := git(ctx, u.Env, u.Dir, "remote", "get-url", "origin")
	if err != nil {
		return ""
	}
	return GitHubURL(url)
}

// GitHubURL converts a GitHub remote (https, scp-style, or ssh://) to its
// https URL without .git, or "" for any other host.
func GitHubURL(remote string) string {
	url := strings.TrimSuffix(remote, ".git")
	url = replacePrefix(url, "git@github.com:", "https://github.com/")
	url = replacePrefix(url, "ssh://git@github.com/", "https://github.com/")
	if !strings.HasPrefix(url, "https://github.com/") {
		return ""
	}
	return url
}

func replacePrefix(s, old, new string) string {
	if rest, ok := strings.CutPrefix(s, old); ok {
		return new + rest
	}
	return s
}
