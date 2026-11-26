package install

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/arbourd/dotfiles/internal/env"
	"github.com/arbourd/dotfiles/internal/env/envtest"
	"github.com/arbourd/dotfiles/internal/ui"
)

const fisherScript = "function fisher; end\n"

func write(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

// serve points url at an httptest server for the test's lifetime.
func serve(t *testing.T, url *string, body string) {
	t.Helper()
	serveFunc(t, url, func(w http.ResponseWriter, _ *http.Request) { w.Write([]byte(body)) })
}

// serveFunc is serve with a custom handler, for asserting on requests or failing them.
func serveFunc(t *testing.T, url *string, h http.HandlerFunc) {
	t.Helper()
	srv := httptest.NewServer(h)
	old := *url
	*url = srv.URL
	t.Cleanup(func() { *url = old; srv.Close() })
}

func newUI(t *testing.T, verbose bool) (*ui.UI, *envtest.Env) {
	t.Helper()
	e := envtest.New(t)
	return ui.New(e.Env, t.TempDir(), verbose), e
}

func TestRequire(t *testing.T) {
	t.Parallel()
	u, e := newUI(t, false)
	e.Fake.Succeed("have")
	if err := require(u, "have"); err != nil {
		t.Fatal(err)
	}
	err := require(u, "have", "missing_cmd")
	if err == nil || err.Error() != "Error: 'missing_cmd' is required but not installed." {
		t.Fatalf("err = %v", err)
	}
}

func TestBrewBundlesWithoutLockfile(t *testing.T) {
	t.Parallel()
	u, e := newUI(t, false)
	var got env.Cmd
	e.Fake.Handle("brew", func(c env.Cmd) error { got = c; return nil })

	if err := Brew(context.Background(), u); err != nil {
		t.Fatal(err)
	}
	want := "brew bundle --file " + u.Dir + "/Brewfile"
	if lines := e.Fake.Lines(); !slices.Equal(lines, []string{want}) {
		t.Fatalf("lines = %q", lines)
	}
	if !slices.Contains(got.Env, "HOMEBREW_BUNDLE_NO_LOCK=1") {
		t.Fatalf("env = %q", got.Env)
	}
	if out := e.Out.String(); !strings.Contains(out, "homebrew installed") || !strings.Contains(out, "homebrew packages") {
		t.Fatalf("out = %q", out)
	}
}

func TestBrewInstallsWhenMissing(t *testing.T) {
	serve(t, &BrewInstallURL, "echo installer")
	u, e := newUI(t, false)
	e.Fake.Handle("/bin/bash", func(env.Cmd) error { e.Fake.Succeed("brew"); return nil })

	if err := Brew(context.Background(), u); err != nil {
		t.Fatal(err)
	}
	want := []string{"/bin/bash -c echo installer", "brew bundle --file " + u.Dir + "/Brewfile"}
	if lines := e.Fake.Lines(); !slices.Equal(lines, want) {
		t.Fatalf("lines = %q", lines)
	}
}

func TestDefaults(t *testing.T) {
	t.Parallel()
	u, e := newUI(t, false)
	e.Fake.Succeed(u.Dir + "/.macOS")
	if err := Defaults(context.Background(), u); err != nil {
		t.Fatal(err)
	}
	if lines := e.Fake.Lines(); !slices.Equal(lines, []string{u.Dir + "/.macOS"}) {
		t.Fatalf("lines = %q", lines)
	}
}

func TestFisherRestoresPluginsFromDotfilesRepo(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not installed")
	}
	u, e := newUI(t, false)
	repo := u.Dir
	write(t, filepath.Join(repo, "sh", "fish_plugins"), "jorgebucaran/fisher@1.2.3\n")
	git := func(args ...string) {
		t.Helper()
		args = append([]string{"-C", repo, "-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false"}, args...)
		if out, err := exec.Command("git", args...).CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	git("init", "-q")
	git("add", "sh/fish_plugins")
	git("commit", "-q", "-m", "init")
	write(t, filepath.Join(repo, "sh", "fish_plugins"), "modified\n")

	write(t, filepath.Join(e.Home, ".config", "fish", "fish_plugins"), "")
	var path string
	serveFunc(t, &FisherBaseURL, func(w http.ResponseWriter, r *http.Request) {
		path = r.URL.Path
		w.Write([]byte(fisherScript))
	})
	e.Fake.Succeed("brew")
	e.Fake.Succeed("curl")
	var stdin []byte
	e.Fake.Handle("fish", func(c env.Cmd) error { stdin, _ = io.ReadAll(c.Stdin); return nil })
	e.Fake.Real = map[string]bool{"git": true}
	t.Chdir(t.TempDir())

	if err := Fisher(context.Background(), u); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(filepath.Join(repo, "sh", "fish_plugins"))
	if string(got) != "jorgebucaran/fisher@1.2.3\n" {
		t.Fatalf("fish_plugins = %q", got)
	}
	lines := e.Fake.Lines()
	if len(lines) != 2 || lines[0] != "git -C "+repo+" checkout sh/fish_plugins" {
		t.Fatalf("lines = %q", lines)
	}
	if lines[1] != "fish -c source - && fisher update" {
		t.Fatalf("fish line = %q", lines[1])
	}
	if path != "/1.2.3/functions/fisher.fish" {
		t.Fatalf("path = %q", path)
	}
	if string(stdin) != fisherScript {
		t.Fatalf("stdin = %q", stdin)
	}
	if fi, err := os.Stat(filepath.Join(e.Home, ".config", "fish", "functions")); err != nil || !fi.IsDir() {
		t.Fatalf("functions dir missing: %v", err)
	}
}

func TestFisherInstallsFishWhenMissing(t *testing.T) {
	serve(t, &FisherBaseURL, fisherScript)
	u, e := newUI(t, false)
	write(t, filepath.Join(e.Home, ".config", "fish", "fish_plugins"), "")
	write(t, filepath.Join(u.Dir, "sh", "fish_plugins"), "jorgebucaran/fisher@9.9.9\n")
	for _, c := range []string{"curl", "git"} {
		e.Fake.Succeed(c)
	}
	e.Fake.Handle("brew", func(env.Cmd) error { e.Fake.Succeed("fish"); return nil })

	if err := Fisher(context.Background(), u); err != nil {
		t.Fatal(err)
	}
	want := []string{"brew install fish", "git -C " + u.Dir + " checkout sh/fish_plugins", "fish -c source - && fisher update"}
	if lines := e.Fake.Lines(); !slices.Equal(lines, want) {
		t.Fatalf("lines = %q", lines)
	}
}

func TestFisherDownloadFailureSkipsFish(t *testing.T) {
	serveFunc(t, &FisherBaseURL, func(w http.ResponseWriter, _ *http.Request) { http.NotFound(w, nil) })
	u, e := newUI(t, false)
	write(t, filepath.Join(e.Home, ".config", "fish", "fish_plugins"), "")
	write(t, filepath.Join(u.Dir, "sh", "fish_plugins"), "jorgebucaran/fisher@9.9.9\n")
	for _, c := range []string{"brew", "curl", "git", "fish"} {
		e.Fake.Succeed(c)
	}

	err := Fisher(context.Background(), u)
	if err == nil || !strings.Contains(err.Error(), "404") {
		t.Fatalf("err = %v", err)
	}
	for _, l := range e.Fake.Lines() {
		if strings.HasPrefix(l, "fish ") {
			t.Fatalf("fish ran: %q", l)
		}
	}
}

func TestFisherAndVimFailBeforeLink(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name string
		step func(context.Context, *ui.UI) error
		want string
	}{
		{"fisher", Fisher, "Error: ~/.config/fish/fish_plugins not found; run 'dot link' first."},
		{"vim", Vim, "Error: ~/.vim/vimrc not found; run 'dot link' first."},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			u, e := newUI(t, false)
			for _, c := range []string{"brew", "curl", "git", "fish", "vim"} {
				e.Fake.Succeed(c)
			}
			err := tc.step(context.Background(), u)
			if err == nil || err.Error() != tc.want {
				t.Fatalf("err = %v, want %q", err, tc.want)
			}
		})
	}
}

func TestVimOutput(t *testing.T) {
	serve(t, &VimPlugURL, "\" plug")
	for _, tc := range []struct {
		name    string
		verbose bool
		fail    bool
		show    bool
	}{
		{"hidden on success", false, false, false},
		{"shown with verbose", true, false, true},
		{"shown on failure", false, true, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			u, e := newUI(t, tc.verbose)
			write(t, filepath.Join(e.Home, ".vim", "vimrc"), "")
			var stdin []byte
			e.Fake.Handle("vim", func(c env.Cmd) error {
				stdin = make([]byte, 8)
				n, _ := c.Stdin.Read(stdin)
				stdin = stdin[:n]
				c.Stdout.Write([]byte("vim-output\n"))
				if tc.fail {
					return os.ErrInvalid
				}
				return nil
			})

			err := Vim(context.Background(), u)
			if (err != nil) != tc.fail {
				t.Fatalf("err = %v", err)
			}
			all := e.Out.String() + e.ErrOut.String()
			if got := strings.Contains(all, "vim-output"); got != tc.show {
				t.Fatalf("output shown = %v, want %v\n%s", got, tc.show, all)
			}
			if string(stdin) != "\n\n" {
				t.Fatalf("stdin = %q", stdin)
			}
			if lines := e.Fake.Lines(); !slices.Equal(lines, []string{"vim +PlugUpdate +PlugClean! +qall"}) {
				t.Fatalf("lines = %q", lines)
			}
			plug, err := os.ReadFile(filepath.Join(e.Home, ".vim", "autoload", "plug.vim"))
			if err != nil || string(plug) != "\" plug" {
				t.Fatalf("plug.vim = %q, %v", plug, err)
			}
		})
	}
}
