package repo

import (
	"context"
	"errors"
	"io"
	"io/fs"
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

func run(t *testing.T, args ...string) string {
	t.Helper()
	base := []string{
		"-c", "user.name=test", "-c", "user.email=test@example.com",
		"-c", "commit.gpgsign=false", "-c", "init.defaultBranch=main",
	}
	out, err := exec.Command("git", append(base, args...)...).CombinedOutput()
	if err != nil {
		t.Fatalf("git %s: %v\n%s", strings.Join(args, " "), err, out)
	}
	return strings.TrimSpace(string(out))
}

// fixture creates a working repository and a bare clone that supports blobless clones.
type fixture struct {
	src, url string
}

func newFixture(t *testing.T) fixture {
	t.Helper()
	root := t.TempDir()
	src := filepath.Join(root, "src")
	files := []string{
		"Brewfile", ".macOS", "sh/.shrc", "git/config", "agents/AGENTS.md", "agents/claude/settings.jsonc",
		"cmd/dot/main.go", "internal/repo/repo.go", "go.mod", "go.sum", ".goreleaser.yaml",
		"dot", "install.sh", "README.md", "LICENSE", "AGENTS.md", "SPEC.md", ".gitignore",
		"tests/dot_test.nu", ".github/workflows/ci.yml", ".agents/skills/x/SKILL.md", ".claude/skills",
		"agents/skills.json", "agents/vendor-skills", "newdir/file",
	}
	for _, f := range files {
		p := filepath.Join(src, f)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(f+"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	run(t, "-C", src, "init", "-q")
	run(t, "-C", src, "add", "-A")
	run(t, "-C", src, "commit", "-q", "-m", "init")

	bare := filepath.Join(root, "bare.git")
	run(t, "clone", "-q", "--bare", src, bare)
	// The bare server must allow filters for blobless clones.
	run(t, "-C", bare, "config", "uploadpack.allowFilter", "true")
	return fixture{src: src, url: "file://" + bare}
}

func (f fixture) push(t *testing.T) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(f.src, "new"), []byte("new\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	run(t, "-C", f.src, "add", "-A")
	run(t, "-C", f.src, "commit", "-q", "-m", "new")
	run(t, "-C", f.src, "push", "-q", strings.TrimPrefix(f.url, "file://"), "HEAD:main")
}

func realUI(t *testing.T, dir string) (*ui.UI, *envtest.Env) {
	t.Helper()
	e := envtest.New(t)
	e.Fake.Real = map[string]bool{"git": true}
	return ui.New(e.Env, dir, false), e
}

func TestInitFreshCloneIsSparse(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	u, e := realUI(t, "")
	u.Dir = filepath.Join(e.Home, ".local", "share", "dotfiles")

	if err := initFrom(context.Background(), u, f.url, SparsePatterns); err != nil {
		t.Fatalf("init: %v\n%s", err, e.ErrOut)
	}
	if got, want := checkedOut(t, u.Dir), runtimeFiles; !slices.Equal(got, want) {
		t.Errorf("fresh clone has %q, want only %q", got, want)
	}
	for _, p := range runtimeFiles {
		if _, err := os.Stat(filepath.Join(u.Dir, p)); err != nil {
			t.Errorf("%s missing from a fresh clone: %v", p, err)
		}
	}
	if got := run(t, "-C", u.Dir, "config", "--get", "core.sparseCheckout"); got != "true" {
		t.Errorf("core.sparseCheckout = %q, want true", got)
	}
	if got := run(t, "-C", u.Dir, "config", "--get", "remote.origin.promisor"); got != "true" {
		t.Errorf("remote.origin.promisor = %q, want true (blobless)", got)
	}
	if !strings.Contains(e.Out.String(), "ok       cloning dotfiles") {
		t.Errorf("output missing clone status:\n%s", e.Out)
	}
}

var runtimeFiles = []string{".macOS", "Brewfile", "agents/AGENTS.md", "agents/claude/settings.jsonc", "git/config", "sh/.shrc"}

func checkedOut(t *testing.T, dir string) []string {
	t.Helper()
	var out []string
	err := filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() && d.Name() == ".git" {
			return filepath.SkipDir
		}
		if !d.IsDir() {
			rel, _ := filepath.Rel(dir, p)
			out = append(out, rel)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	slices.Sort(out)
	return out
}

func TestUpdateReappliesPatternsToSparseClone(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	u, e := realUI(t, "")
	u.Dir = filepath.Join(e.Home, "dotfiles")
	if err := initFrom(context.Background(), u, f.url, SparsePatterns); err != nil {
		t.Fatalf("init: %v\n%s", err, e.ErrOut)
	}
	if _, err := os.Stat(filepath.Join(u.Dir, "newdir")); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("newdir checked out before it is allowlisted: %v", err)
	}

	// a newer dot that allowlists newdir
	if err := update(context.Background(), u, append(slices.Clone(SparsePatterns), "/newdir/")); err != nil {
		t.Fatalf("update: %v\n%s", err, e.ErrOut)
	}
	if _, err := os.Stat(filepath.Join(u.Dir, "newdir", "file")); err != nil {
		t.Errorf("update did not check out the newly allowlisted folder: %v", err)
	}
}

func TestUpdateLeavesFullCloneFull(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	u, e := realUI(t, "")
	u.Dir = filepath.Join(e.Home, "dotfiles")
	run(t, "clone", "-q", f.url, u.Dir)

	if err := Update(context.Background(), u); err != nil {
		t.Fatalf("update: %v\n%s", err, e.ErrOut)
	}
	if err := exec.Command("git", "-C", u.Dir, "config", "--get", "core.sparseCheckout").Run(); err == nil {
		t.Error("update made a full clone sparse")
	}
	if _, err := os.Stat(filepath.Join(u.Dir, "go.mod")); err != nil {
		t.Errorf("full clone lost go.mod: %v", err)
	}
}

func TestInitExistingClonePullsAndStaysFull(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	u, e := realUI(t, "")
	u.Dir = filepath.Join(e.Home, "dotfiles")
	run(t, "clone", "-q", f.url, u.Dir)
	f.push(t)

	if err := initFrom(context.Background(), u, f.url, SparsePatterns); err != nil {
		t.Fatalf("init: %v\n%s", err, e.ErrOut)
	}
	if _, err := os.Stat(filepath.Join(u.Dir, "new")); err != nil {
		t.Errorf("pull did not bring in the new commit: %v", err)
	}
	if _, err := os.Stat(filepath.Join(u.Dir, "go.mod")); err != nil {
		t.Errorf("existing clone lost go.mod: %v", err)
	}
	if err := exec.Command("git", "-C", u.Dir, "config", "--get", "core.sparseCheckout").Run(); err == nil {
		t.Error("core.sparseCheckout is set on an existing clone")
	}
	want := "ok       " + "~/dotfiles already exists, pulling"
	if !strings.Contains(e.Out.String(), want) {
		t.Errorf("output missing %q:\n%s", want, e.Out)
	}
}

// Pins zsh init's clone and update behavior; install.sh owns symlink creation.
func TestInitCommands(t *testing.T) {
	t.Parallel()
	sparse := strings.Join(SparsePatterns, " ")
	tests := map[string]struct {
		exists  bool
		verbose bool
		want    func(dir string) []string
	}{
		"missing target clones": {
			want: func(dir string) []string {
				return []string{
					"git clone --filter=blob:none --no-checkout https://example.com/d.git " + dir,
					"git -C " + dir + " sparse-checkout set --no-cone " + sparse,
					"git -C " + dir + " checkout",
				}
			},
		},
		"missing target verbose": {
			verbose: true,
			want: func(dir string) []string {
				return []string{
					"git clone --filter=blob:none --no-checkout -v https://example.com/d.git " + dir,
					"git -C " + dir + " sparse-checkout set --no-cone " + sparse,
					"git -C " + dir + " checkout",
				}
			},
		},
		"existing target pulls": {
			exists: true,
			want:   func(dir string) []string { return []string{"git -C " + dir + " pull"} },
		},
		"existing target verbose": {
			exists:  true,
			verbose: true,
			want:    func(dir string) []string { return []string{"git -C " + dir + " pull -v"} },
		},
	}
	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			e := envtest.New(t)
			e.Fake.Succeed("git")
			dir := filepath.Join(e.Home, "src", "github.com", "arbourd", "dotfiles")
			if tt.exists {
				if err := os.MkdirAll(dir, 0o755); err != nil {
					t.Fatal(err)
				}
			}
			u := ui.New(e.Env, dir, tt.verbose)

			if err := initFrom(context.Background(), u, "https://example.com/d.git", SparsePatterns); err != nil {
				t.Fatal(err)
			}
			if got, want := e.Fake.Lines(), tt.want(dir); !slices.Equal(got, want) {
				t.Errorf("commands:\n got %q\nwant %q", got, want)
			}
			if fi, err := os.Stat(filepath.Dir(dir)); err != nil || !fi.IsDir() {
				t.Errorf("parent dir not created: %v", err)
			}
			if !strings.Contains(e.Out.String(), "Initializing dotfiles") {
				t.Errorf("output missing header:\n%s", e.Out)
			}
		})
	}
}

func TestInitCloneFailureStops(t *testing.T) {
	t.Parallel()
	e := envtest.New(t)
	e.Fake.Fail("git", "fatal: repository not found\n")
	u := ui.New(e.Env, filepath.Join(e.Home, "dotfiles"), false)

	if err := Init(context.Background(), u); err == nil {
		t.Fatal("init succeeded after a failed clone")
	}
	if got := e.Fake.Lines(); len(got) != 1 || !strings.HasPrefix(got[0], "git clone ") {
		t.Errorf("commands after a failed clone = %q, want only the clone", got)
	}
	if !strings.Contains(e.ErrOut.String(), "repository not found") {
		t.Errorf("stderr missing git output:\n%s", e.ErrOut)
	}
}

func TestInitRemovesHalfMadeClone(t *testing.T) {
	t.Parallel()
	e := envtest.New(t)
	dir := filepath.Join(e.Home, "dotfiles")
	e.Fake.Handle("git", func(c env.Cmd) error {
		if c.Args[0] == "clone" {
			return os.MkdirAll(filepath.Join(dir, ".git"), 0o755)
		}
		return errors.New("sparse-checkout failed")
	})
	u := ui.New(e.Env, dir, false)

	if err := Init(context.Background(), u); err == nil {
		t.Fatal("init succeeded after a failed sparse-checkout")
	}
	if _, err := os.Stat(dir); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("half-made clone left behind: %v", err)
	}
}

// Pins zsh update's status and commit reporting against real git.
func TestUpdate(t *testing.T) {
	t.Parallel()
	tests := map[string]struct {
		push bool
		want func(before, after string) string
	}{
		"up to date": {
			want: func(_, after string) string { return "ok       dotfiles " + after + " (up to date)" },
		},
		"changed": {
			push: true,
			want: func(before, after string) string { return "updated  dotfiles " + before + " → " + after },
		},
	}
	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			f := newFixture(t)
			u, e := realUI(t, "")
			u.Dir = filepath.Join(e.Home, "dotfiles")
			run(t, "clone", "-q", f.url, u.Dir)
			before := run(t, "-C", u.Dir, "rev-parse", "--short", "HEAD")
			if tt.push {
				f.push(t)
			}

			if err := Update(context.Background(), u); err != nil {
				t.Fatalf("update: %v\n%s", err, e.ErrOut)
			}
			after := run(t, "-C", u.Dir, "rev-parse", "--short", "HEAD")
			if tt.push == (before == after) {
				t.Fatalf("HEAD %s → %s, push %v", before, after, tt.push)
			}
			out := e.Out.String()
			for _, want := range []string{"ok       pulling dotfiles", tt.want(before, after)} {
				if !strings.Contains(out, want) {
					t.Errorf("output missing %q:\n%s", want, out)
				}
			}
		})
	}
}

func TestUpdateHyperlinks(t *testing.T) {
	t.Parallel()
	const repo = "https://github.com/arbourd/dotfiles"
	tests := map[string]struct {
		after string
		want  string
	}{
		"up to date": {"abc1234", "\x1b]8;;" + repo + "/commit/abc1234\x1b\\abc1234\x1b]8;;\x1b\\"},
		"changed":    {"def5678", "\x1b]8;;" + repo + "/compare/abc1234...def5678\x1b\\abc1234 → def5678\x1b]8;;\x1b\\"},
	}
	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			e := envtest.New(t)
			e.StdoutTTY = true
			pulled := false
			e.Fake.Handle("git", func(c env.Cmd) error {
				switch args := strings.Join(c.Args, " "); {
				case strings.HasSuffix(args, "rev-parse --short HEAD"):
					sha := "abc1234"
					if pulled {
						sha = tt.after
					}
					io.WriteString(c.Stdout, sha+"\n")
				case strings.Contains(args, "pull --quiet"):
					pulled = true
				case strings.HasSuffix(args, "remote get-url origin"):
					io.WriteString(c.Stdout, "git@github.com:arbourd/dotfiles.git\n")
				}
				return nil
			})
			u := ui.New(e.Env, filepath.Join(e.Home, "dotfiles"), false)
			u.FrameInterval = 1 << 62 // draw one frame only

			if err := Update(context.Background(), u); err != nil {
				t.Fatal(err)
			}
			if !strings.Contains(e.Out.String(), tt.want) {
				t.Errorf("output missing %q:\n%q", tt.want, e.Out)
			}
		})
	}
}

func TestUpdatePullFailure(t *testing.T) {
	t.Parallel()
	e := envtest.New(t)
	e.Fake.Handle("git", func(c env.Cmd) error {
		if slices.Contains(c.Args, "pull") {
			io.WriteString(c.Stderr, "fatal: no upstream\n")
			return exec.ErrNotFound
		}
		io.WriteString(c.Stdout, "abc1234\n")
		return nil
	})
	u := ui.New(e.Env, filepath.Join(e.Home, "dotfiles"), false)

	if err := Update(context.Background(), u); err == nil {
		t.Fatal("update succeeded after a failed pull")
	}
	if strings.Contains(e.Out.String(), "dotfiles abc1234") {
		t.Errorf("reported a result after a failed pull:\n%s", e.Out)
	}
}

// Pins zsh dot's empty URL behavior when origin is missing.
func TestURLWithoutOrigin(t *testing.T) {
	t.Parallel()
	u, e := realUI(t, "")
	u.Dir = filepath.Join(e.Home, "repo")
	run(t, "init", "-q", u.Dir)

	if got := URL(context.Background(), u); got != "" {
		t.Errorf("URL() = %q, want empty", got)
	}
}
