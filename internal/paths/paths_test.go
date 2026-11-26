package paths

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/arbourd/dotfiles/internal/env/envtest"
	"github.com/arbourd/dotfiles/internal/ui"
)

func newUI(t *testing.T) (*ui.UI, *envtest.Env) {
	t.Helper()
	e := envtest.New(t)
	return ui.New(e.Env, "", false), e
}

func mustSymlink(t *testing.T, target, link string) {
	t.Helper()
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}
}

func isLink(p string) bool {
	fi, err := os.Lstat(p)
	return err == nil && fi.Mode()&os.ModeSymlink != 0
}

func TestDotfilesPath(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name         string
		dotDir, xdg  string
		want, wantDf string // relative to home, except absolute DOT_DIR values
	}{
		{name: "default", want: ".local/share/dotfiles", wantDf: ".local/share/dotfiles"},
		{name: "xdg", xdg: "/xdg/data", want: "/xdg/data/dotfiles", wantDf: "/xdg/data/dotfiles"},
		{name: "dot dir wins", dotDir: "/dev/dotfiles", xdg: "/xdg/data", want: "/dev/dotfiles", wantDf: "/xdg/data/dotfiles"},
		{name: "cleaned", dotDir: "/dev/x/../dotfiles/", want: "/dev/dotfiles", wantDf: ".local/share/dotfiles"},
		{name: "spaces", dotDir: "/path with spaces/dotfiles", want: "/path with spaces/dotfiles", wantDf: ".local/share/dotfiles"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			e := envtest.New(t)
			e.DotDir, e.XDGDataHome = tt.dotDir, tt.xdg
			resolve := func(p string) string {
				if filepath.IsAbs(p) {
					return p
				}
				return filepath.Join(e.Home, p)
			}
			if got, want := DotfilesPath(e.Env), resolve(tt.want); got != want {
				t.Errorf("DotfilesPath = %q, want %q", got, want)
			}
			if got, want := DefaultPath(e.Env), resolve(tt.wantDf); got != want {
				t.Errorf("DefaultPath = %q, want %q", got, want)
			}
		})
	}
}

func TestWarnLocation(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name string
		// setup returns DOT_DIR for an env whose default path is <home>/.local/share/dotfiles.
		setup func(t *testing.T, home string) string
		warn  bool
	}{
		{"unset", func(*testing.T, string) string { return "" }, false},
		{"equal to default", func(_ *testing.T, h string) string { return filepath.Join(h, ".local/share/dotfiles") }, false},
		{"other checkout", func(_ *testing.T, h string) string { return filepath.Join(h, "src/dotfiles") }, true},
		{"symlink to default", func(t *testing.T, h string) string {
			def := filepath.Join(h, ".local/share/dotfiles")
			if err := os.MkdirAll(def, 0o755); err != nil {
				t.Fatal(err)
			}
			link := filepath.Join(h, "alias")
			mustSymlink(t, def, link)
			return link
		}, false},
		{"existing other dir", func(t *testing.T, h string) string {
			if err := os.MkdirAll(filepath.Join(h, ".local/share/dotfiles"), 0o755); err != nil {
				t.Fatal(err)
			}
			other := filepath.Join(h, "other")
			if err := os.Mkdir(other, 0o755); err != nil {
				t.Fatal(err)
			}
			return other
		}, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			u, e := newUI(t)
			e.DotDir = tt.setup(t, e.Home)
			WarnLocation(u, e.Env)
			got := e.Out.String()
			if !tt.warn {
				if got != "" {
					t.Fatalf("unexpected output %q", got)
				}
				return
			}
			want := u.Tilde("running from " + DotfilesPath(e.Env) + ", not " + DefaultPath(e.Env))
			if !strings.HasPrefix(got, "warn") || !strings.Contains(got, want) {
				t.Fatalf("output %q, want warn with %q", got, want)
			}
		})
	}
}

func TestEnsure(t *testing.T) {
	t.Parallel()
	t.Run("creates parents and file", func(t *testing.T) {
		t.Parallel()
		p := filepath.Join(t.TempDir(), "a b", "c", "file")
		if err := Ensure(p, 0); err != nil {
			t.Fatal(err)
		}
		if fi, err := os.Stat(p); err != nil || !fi.Mode().IsRegular() {
			t.Fatalf("want regular file, got %v, %v", fi, err)
		}
	})
	t.Run("trailing slash makes a directory", func(t *testing.T) {
		t.Parallel()
		p := filepath.Join(t.TempDir(), "x", "dir")
		if err := Ensure(p+"/", 0o700); err != nil {
			t.Fatal(err)
		}
		fi, err := os.Stat(p)
		if err != nil || !fi.IsDir() || fi.Mode().Perm() != 0o700 {
			t.Fatalf("want 0700 dir, got %v, %v", fi, err)
		}
	})
	t.Run("leaves existing files untouched", func(t *testing.T) {
		t.Parallel()
		p := filepath.Join(t.TempDir(), "cfg", "private")
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte("secret\n"), 0o644); err != nil {
			t.Fatal(err)
		}
		if err := Ensure(p, 0); err != nil {
			t.Fatal(err)
		}
		if b, _ := os.ReadFile(p); string(b) != "secret\n" {
			t.Fatalf("contents = %q", b)
		}
		if err := Ensure(p, 0o600); err != nil {
			t.Fatal(err)
		}
		fi, _ := os.Stat(p)
		if b, _ := os.ReadFile(p); string(b) != "secret\n" || fi.Mode().Perm() != 0o600 {
			t.Fatalf("contents = %q, mode = %v", b, fi.Mode().Perm())
		}
	})
}

func TestSymlink(t *testing.T) {
	t.Parallel()
	t.Run("creates a link and reports it", func(t *testing.T) {
		t.Parallel()
		u, e := newUI(t)
		src, link := filepath.Join(e.Home, "src dir", "file"), filepath.Join(e.Home, "link")
		if err := Symlink(u, src, link); err != nil {
			t.Fatal(err)
		}
		if got, _ := os.Readlink(link); got != src {
			t.Fatalf("target = %q, want %q", got, src)
		}
		if want := "linked   ~/link → ~/src dir/file\n"; e.Out.String() != want {
			t.Fatalf("output %q, want %q", e.Out.String(), want)
		}
	})
	t.Run("replaces a file and a symlink", func(t *testing.T) {
		t.Parallel()
		u, e := newUI(t)
		file, other := filepath.Join(e.Home, "file"), filepath.Join(e.Home, "other")
		mustSymlink(t, "/old", other)
		if err := os.WriteFile(file, nil, 0o644); err != nil {
			t.Fatal(err)
		}
		for _, link := range []string{file, other} {
			if err := Symlink(u, "/new", link); err != nil {
				t.Fatal(err)
			}
			if got, _ := os.Readlink(link); got != "/new" {
				t.Fatalf("%s -> %q", link, got)
			}
		}
	})
	t.Run("into a real directory uses the source base name", func(t *testing.T) {
		t.Parallel()
		u, e := newUI(t)
		dir := filepath.Join(e.Home, "bin")
		if err := os.Mkdir(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := Symlink(u, "/repo/sh/dot", dir); err != nil {
			t.Fatal(err)
		}
		if got, _ := os.Readlink(filepath.Join(dir, "dot")); got != "/repo/sh/dot" {
			t.Fatalf("target = %q", got)
		}
		if !strings.Contains(e.Out.String(), "~/bin/dot → /repo/sh/dot") {
			t.Fatalf("output %q", e.Out.String())
		}
	})
	t.Run("into a symlink to a directory keeps the directory link", func(t *testing.T) {
		t.Parallel()
		u, e := newUI(t)
		real, link := filepath.Join(e.Home, "real"), filepath.Join(e.Home, "skills")
		if err := os.Mkdir(real, 0o755); err != nil {
			t.Fatal(err)
		}
		mustSymlink(t, real, link)
		if err := Symlink(u, "/repo/agents/skills/a", link); err != nil {
			t.Fatal(err)
		}
		if got, _ := os.Readlink(link); got != real {
			t.Fatalf("directory link replaced: -> %q", got)
		}
		if got, _ := os.Readlink(filepath.Join(real, "a")); got != "/repo/agents/skills/a" {
			t.Fatalf("target = %q", got)
		}
	})
}

func TestRemoveStaleLink(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name  string
		setup func(t *testing.T, home, prefix string) string // returns the link path
		want  bool
	}{
		{"missing path", func(_ *testing.T, h, _ string) string { return filepath.Join(h, "nope") }, false},
		{"real file", func(t *testing.T, h, _ string) string {
			p := filepath.Join(h, "real-file")
			if err := os.WriteFile(p, nil, 0o644); err != nil {
				t.Fatal(err)
			}
			return p
		}, false},
		{"live link", func(t *testing.T, h, pre string) string {
			if err := os.WriteFile(filepath.Join(pre, "live"), nil, 0o644); err != nil {
				t.Fatal(err)
			}
			p := filepath.Join(h, "live-link")
			mustSymlink(t, filepath.Join(pre, "live"), p)
			return p
		}, false},
		{"external link", func(t *testing.T, h, _ string) string {
			p := filepath.Join(h, "external-link")
			mustSymlink(t, "/etc/hosts", p)
			return p
		}, false},
		{"dangling external", func(t *testing.T, h, _ string) string {
			p := filepath.Join(h, "dangling-external")
			mustSymlink(t, "/nonexistent-outside-prefix", p)
			return p
		}, false},
		{"stale link", func(t *testing.T, h, pre string) string {
			p := filepath.Join(h, "stale-link")
			mustSymlink(t, filepath.Join(pre, "nonexistent"), p)
			return p
		}, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			u, e := newUI(t)
			prefix := filepath.Join(e.Home, "path with spaces") + "/"
			if err := os.Mkdir(prefix, 0o755); err != nil {
				t.Fatal(err)
			}
			link := tt.setup(t, e.Home, prefix)
			_, errBefore := os.Lstat(link)
			got, err := RemoveStaleLink(u, link, prefix)
			if err != nil || got != tt.want {
				t.Fatalf("got %v, %v, want %v", got, err, tt.want)
			}
			if _, err := os.Lstat(link); (err == nil) != (errBefore == nil && !tt.want) {
				t.Fatalf("existence after = %v, before = %v, removed = %v", err == nil, errBefore == nil, tt.want)
			}
			if tt.want != strings.HasPrefix(e.Out.String(), "removed") {
				t.Fatalf("output %q", e.Out.String())
			}
		})
	}
}

func TestCleanDir(t *testing.T) {
	t.Parallel()
	t.Run("protects real files and unrelated symlinks", func(t *testing.T) {
		t.Parallel()
		u, e := newUI(t)
		prefix := filepath.Join(e.Home, "dotfiles") + "/"
		ssh := filepath.Join(e.Home, ".ssh")
		if err := os.Mkdir(ssh, 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(ssh, "id_rsa"), nil, 0o600); err != nil {
			t.Fatal(err)
		}
		mustSymlink(t, "/etc/hosts", filepath.Join(ssh, "external_link"))
		mustSymlink(t, prefix+"nonexistent", filepath.Join(ssh, "stale_link"))
		mustSymlink(t, prefix+"nonexistent", filepath.Join(ssh, ".hidden_stale"))

		missing := filepath.Join(e.Home, "missing")
		if err := CleanDir(u, prefix, missing, ssh); err != nil {
			t.Fatal(err)
		}
		if fi, err := os.Lstat(filepath.Join(ssh, "id_rsa")); err != nil || !fi.Mode().IsRegular() {
			t.Fatalf("real file damaged: %v", err)
		}
		if got, _ := os.Readlink(filepath.Join(ssh, "external_link")); got != "/etc/hosts" {
			t.Fatalf("external link = %q", got)
		}
		for _, n := range []string{"stale_link", ".hidden_stale"} {
			if isLink(filepath.Join(ssh, n)) {
				t.Fatalf("%s survived", n)
			}
		}
		out := e.Out.String()
		if strings.Count(out, "removed") != 2 || strings.Contains(out, "none found") {
			t.Fatalf("output %q", out)
		}
	})
	t.Run("reports none found", func(t *testing.T) {
		t.Parallel()
		u, e := newUI(t)
		if err := CleanDir(u, "/prefix/", e.Home, filepath.Join(e.Home, "missing")); err != nil {
			t.Fatal(err)
		}
		if want := "ok       none found\n"; e.Out.String() != want {
			t.Fatalf("output %q, want %q", e.Out.String(), want)
		}
	})
}
