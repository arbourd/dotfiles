package repo

import "testing"

func TestGitHubURL(t *testing.T) {
	t.Parallel()
	tests := map[string]string{
		"https://github.com/arbourd/dotfiles.git":   "https://github.com/arbourd/dotfiles",
		"https://github.com/arbourd/dotfiles":       "https://github.com/arbourd/dotfiles",
		"git@github.com:arbourd/dotfiles.git":       "https://github.com/arbourd/dotfiles",
		"ssh://git@github.com/arbourd/dotfiles.git": "https://github.com/arbourd/dotfiles",
		"https://gitlab.com/arbourd/dotfiles.git":   "",
		"/tmp/some/local/path":                      "",
	}
	for in, want := range tests {
		if got := GitHubURL(in); got != want {
			t.Errorf("GitHubURL(%q) = %q, want %q", in, got, want)
		}
	}
}
