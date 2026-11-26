// Package install manages Homebrew, Fisher, vim-plug, and macOS defaults.
package install

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/arbourd/dotfiles/internal/env"
	"github.com/arbourd/dotfiles/internal/paths"
	"github.com/arbourd/dotfiles/internal/ui"
)

func require(u *ui.UI, names ...string) error {
	for _, name := range names {
		if !env.Has(u.Env.Runner, name) {
			return fmt.Errorf("Error: '%s' is required but not installed.", name)
		}
	}
	return nil
}

// client bounds downloads to avoid hanging on a stalled connection.
var client = &http.Client{Timeout: 2 * time.Minute}

func fetch(ctx context.Context, url string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("download %s: %w", url, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("download %s: %s", url, resp.Status)
	}
	return io.ReadAll(resp.Body)
}

// Brew installs Homebrew if missing, then bundles the Brewfile.
func Brew(ctx context.Context, u *ui.UI) error {
	u.Log("Homebrew")
	if !env.Has(u.Env.Runner, "brew") {
		script, err := fetch(ctx, BrewInstallURL)
		if err != nil {
			return err
		}
		// The installer prompts, so it needs the real terminal.
		err = u.Env.Runner.Run(ctx, env.Cmd{
			Name:   "/bin/bash",
			Args:   []string{"-c", string(script)},
			Stdin:  os.Stdin,
			Stdout: u.Env.Stdout,
			Stderr: u.Env.Stderr,
		})
		if err != nil {
			return fmt.Errorf("install homebrew: %w", err)
		}
	}
	u.Status(ui.OK, "homebrew installed")

	return u.SpinCmd(ctx, "homebrew packages", env.Cmd{
		Name: "brew",
		Args: []string{"bundle", "--file", filepath.Join(u.Dir, "Brewfile")},
		Env:  []string{"HOMEBREW_BUNDLE_NO_LOCK=1"},
	})
}

// Defaults applies the macOS defaults in .macOS.
func Defaults(ctx context.Context, u *ui.UI) error {
	u.Log("macOS defaults")
	return u.SpinCmd(ctx, "macos defaults", env.Cmd{Name: filepath.Join(u.Dir, ".macOS")})
}

var fisherVersion = regexp.MustCompile(`jorgebucaran/fisher@(\S+)`)

// Fisher installs Fisher and updates all fish plugins.
func Fisher(ctx context.Context, u *ui.UI) error {
	// curl stays because `fisher update` downloads plugins with it.
	if err := require(u, "brew", "curl", "git"); err != nil {
		return err
	}

	u.Log("Fisher")
	if !env.Has(u.Env.Runner, "fish") {
		if err := u.SpinCmd(ctx, "fish", env.Cmd{Name: "brew", Args: []string{"install", "fish"}}); err != nil {
			return err
		}
	}

	fishDir := filepath.Join(u.Env.Home, ".config", "fish")
	if _, err := os.Stat(filepath.Join(fishDir, "fish_plugins")); err != nil {
		return fmt.Errorf("Error: ~/.config/fish/fish_plugins not found; run 'dot link' first.")
	}

	if err := paths.Ensure(filepath.Join(fishDir, "functions")+"/", 0); err != nil {
		return err
	}
	// fisher's version is pinned in fish_plugins; `fisher install` would conflict with an existing fisher.
	if err := u.Env.Runner.Run(ctx, env.Cmd{
		Name:   "git",
		Args:   []string{"-C", u.Dir, "checkout", "sh/fish_plugins"},
		Stdout: u.Env.Stdout,
		Stderr: u.Env.Stderr,
	}); err != nil {
		return fmt.Errorf("restore sh/fish_plugins: %w", err)
	}

	plugins, err := os.ReadFile(filepath.Join(u.Dir, "sh", "fish_plugins"))
	if err != nil {
		return err
	}
	m := fisherVersion.FindSubmatch(plugins)
	if m == nil {
		return fmt.Errorf("Error: no jorgebucaran/fisher@<version> in sh/fish_plugins.")
	}
	// Downloading here makes a failed fetch an error; fish's `&&` only checks `source`.
	script, err := fetch(ctx, FisherBaseURL+"/"+string(m[1])+"/functions/fisher.fish")
	if err != nil {
		return err
	}
	return u.SpinCmd(ctx, "fisher plugins", env.Cmd{
		Name:  "fish",
		Args:  []string{"-c", "source - && fisher update"},
		Stdin: bytes.NewReader(script),
	})
}

// Vim installs vim-plug and updates every Vim plugin.
func Vim(ctx context.Context, u *ui.UI) error {
	if err := require(u, "vim"); err != nil {
		return err
	}

	u.Log("Vim")
	vimDir := filepath.Join(u.Env.Home, ".vim")
	if _, err := os.Stat(filepath.Join(vimDir, "vimrc")); err != nil {
		return fmt.Errorf("Error: ~/.vim/vimrc not found; run 'dot link' first.")
	}

	autoload := filepath.Join(vimDir, "autoload")
	if err := paths.Ensure(autoload+"/", 0); err != nil {
		return err
	}
	err := u.Spin("vim-plug", func(_, _ io.Writer) error {
		body, err := fetch(ctx, VimPlugURL)
		if err != nil {
			return err
		}
		return os.WriteFile(filepath.Join(autoload, "plug.vim"), body, 0o644)
	})
	if err != nil {
		return err
	}

	return u.Spin("vim plugins", func(stdout, stderr io.Writer) error {
		c := env.Cmd{
			Name: "vim",
			Args: []string{"+PlugUpdate", "+PlugClean!", "+qall"},
			// Two newlines dismiss vim-plug prompts without a tty.
			Stdin: strings.NewReader("\n\n"),
		}
		if u.Verbose {
			c.Stdout, c.Stderr = stdout, stderr
			return u.Env.Runner.Run(ctx, c)
		}
		// Hide vim's output unless it fails.
		var buf bytes.Buffer
		c.Stdout, c.Stderr = &buf, &buf
		err := u.Env.Runner.Run(ctx, c)
		if err != nil {
			stdout.Write(buf.Bytes())
		}
		return err
	})
}
