package link

import (
	"context"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/arbourd/dotfiles/internal/env/envtest"
	"github.com/arbourd/dotfiles/internal/repo"
	"github.com/arbourd/dotfiles/internal/ui"
)

func repoRoot(t testing.TB) string {
	t.Helper()
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	return filepath.Dir(filepath.Dir(wd))
}

func setup(t *testing.T, dir string) (*ui.UI, *envtest.Env) {
	t.Helper()
	e := envtest.New(t)
	return ui.New(e.Env, dir, false), e
}

func runLink(t *testing.T, u *ui.UI) {
	t.Helper()
	if err := Link(context.Background(), u); err != nil {
		t.Fatalf("Link: %v", err)
	}
}

func assertLink(t *testing.T, link, target string) {
	t.Helper()
	got, err := os.Readlink(link)
	if err != nil {
		t.Fatalf("not a symlink: %s: %v", link, err)
	}
	if got != target {
		t.Errorf("%s -> %s, want %s", link, got, target)
	}
}

func perm(t *testing.T, p string) fs.FileMode {
	t.Helper()
	fi, err := os.Stat(p)
	if err != nil {
		t.Fatal(err)
	}
	return fi.Mode().Perm()
}

func TestLinkCreatesDotfileSymlinks(t *testing.T) {
	t.Parallel()
	d := repoRoot(t)
	u, e := setup(t, d)
	runLink(t, u)
	h := e.Home

	links := [][2]string{
		{".bash_profile", "sh/.shrc"},
		{".bashrc", "sh/.shrc"},
		{".zshrc", "sh/.shrc"},
		{".config/fish/config.fish", "sh/config.fish"},
		{".config/fish/fish_plugins", "sh/fish_plugins"},
		{".config/fish/completions/dot.fish", "sh/completions/dot.fish"},
		{".local/share/bash-completion/completions/dot", "sh/completions/dot.bash"},
		{".zsh/completions/_dot", "sh/completions/_dot"},
		{".config/ghostty/config", "ghostty/config"},
		{".config/git/config", "git/config"},
		{".config/git/gitignore", "git/gitignore"},
		{".gnupg/gpg-agent.conf", "gpg/gpg-agent.conf"},
		{".ssh/config", "ssh/config"},
		{".vim/vimrc", "vim/vimrc"},
		{".orca/keybindings.json", "orca/keybindings.json"},
		{".config/zed/settings.json", "zed/settings.json"},
	}
	for _, l := range links {
		assertLink(t, filepath.Join(h, l[0]), filepath.Join(d, l[1]))
	}
	fns, _ := filepath.Glob(filepath.Join(d, "sh/functions/*.fish"))
	for _, fn := range fns {
		assertLink(t, filepath.Join(h, ".config/fish/functions", filepath.Base(fn)), fn)
	}

	if got := perm(t, filepath.Join(h, ".gnupg")); got != 0o700 {
		t.Errorf(".gnupg mode = %v", got)
	}
	for _, f := range []string{".config/fish/private.fish", ".config/git/private"} {
		if got := perm(t, filepath.Join(h, f)); got != 0o600 {
			t.Errorf("%s mode = %v", f, got)
		}
	}
	if !strings.Contains(e.Out.String(), "Run dot merge to merge settings") {
		t.Errorf("missing final log:\n%s", e.Out)
	}
}

func TestLinkIsIdempotentAndPreservesPrivateFiles(t *testing.T) {
	t.Parallel()
	d := repoRoot(t)
	u, e := setup(t, d)
	h := e.Home
	runLink(t, u)
	for _, f := range []string{".config/fish/private.fish", ".config/git/private"} {
		if err := os.WriteFile(filepath.Join(h, f), []byte("secret\n"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	runLink(t, u)

	assertLink(t, filepath.Join(h, ".zshrc"), filepath.Join(d, "sh/.shrc"))
	assertLink(t, filepath.Join(h, ".claude/AGENTS.md"), filepath.Join(d, "agents/AGENTS.md"))
	if _, err := os.Stat(filepath.Join(d, "agents/claude/CLAUDE.md")); err == nil {
		assertLink(t, filepath.Join(h, ".claude/CLAUDE.md"), filepath.Join(d, "agents/claude/CLAUDE.md"))
	}
	for _, f := range []string{".config/fish/private.fish", ".config/git/private"} {
		b, _ := os.ReadFile(filepath.Join(h, f))
		if string(b) != "secret\n" {
			t.Errorf("%s = %q", f, b)
		}
	}
	if _, err := os.Lstat(filepath.Join(h, ".claude/skills/skills")); err == nil {
		t.Error("skills linked into itself")
	}
}

func touch(t *testing.T, p string, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestLinkAgentsCreatesSymlinksWithRenaming(t *testing.T) {
	t.Parallel()
	u, e := setup(t, "")
	h := e.Home
	m := filepath.Join(h, "repo-mock")
	u.Dir = m
	a := filepath.Join(m, "agents")
	for _, f := range []string{"AGENTS.md", "claude/CLAUDE.md", "claude/statusline.nu", "personas/helper.md", "skills/skill-a/SKILL.md", "skills/skill-b/SKILL.md", "codex/config.toml"} {
		touch(t, filepath.Join(a, f), "")
	}
	touch(t, filepath.Join(a, "claude/settings.jsonc"), "{}\n")
	touch(t, filepath.Join(a, "claude/config.jsonc"), "{}\n")

	if err := linkAgents(u); err != nil {
		t.Fatal(err)
	}

	assertLink(t, filepath.Join(h, ".claude/statusline.nu"), filepath.Join(a, "claude/statusline.nu"))
	assertLink(t, filepath.Join(h, ".claude/CLAUDE.md"), filepath.Join(a, "claude/CLAUDE.md"))
	for _, f := range []string{".claude/settings.jsonc", ".claude/config.jsonc"} {
		if _, err := os.Lstat(filepath.Join(h, f)); err == nil {
			t.Errorf("%s should not be linked", f)
		}
	}
	for _, dir := range []string{".claude/agents", ".gemini/agents", ".pi/agent/prompts", ".config/opencode/agents"} {
		assertLink(t, filepath.Join(h, dir, "helper.md"), filepath.Join(a, "personas/helper.md"))
	}
	for _, s := range []string{"skill-a", "skill-b"} {
		assertLink(t, filepath.Join(h, ".claude/skills", s), filepath.Join(a, "skills", s))
		assertLink(t, filepath.Join(h, ".agents/skills", s), filepath.Join(a, "skills", s))
	}
	for _, f := range []string{".claude/AGENTS.md", ".gemini/GEMINI.md", ".codex/AGENTS.md", ".pi/agent/AGENTS.md"} {
		assertLink(t, filepath.Join(h, f), filepath.Join(a, "AGENTS.md"))
	}
}

func TestCleanCoversEveryDirectoryItLists(t *testing.T) {
	t.Parallel()
	d := repoRoot(t)
	u, e := setup(t, d)
	h := e.Home

	// The lists must match the zsh set exactly.
	wantDirs := []string{"", ".config/fish", ".config/fish/completions", ".config/fish/functions", ".config/ghostty", ".config/git", ".config/zed", ".gnupg", ".local/bin", ".local/share/bash-completion/completions", ".orca", ".ssh", ".vim", ".zsh/completions"}
	wantAgentDirs := []string{".claude", ".claude/skills", ".agents/skills", ".claude/agents", ".gemini", ".gemini/agents", ".config/opencode/agents", ".pi/agent", ".pi/agent/prompts", ".codex"}
	if !slices.Equal(CleanDirs, wantDirs) {
		t.Errorf("CleanDirs = %v", CleanDirs)
	}
	if !slices.Equal(CleanAgentDirs, wantAgentDirs) {
		t.Errorf("CleanAgentDirs = %v", CleanAgentDirs)
	}

	mkStale := func(dirs []string, target string) {
		for _, rel := range dirs {
			dir := filepath.Join(h, rel)
			if err := os.MkdirAll(dir, 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.Symlink(target, filepath.Join(dir, "stale")); err != nil {
				t.Fatal(err)
			}
			if err := os.Symlink("/nonexistent-outside-prefix", filepath.Join(dir, "dangling-external")); err != nil {
				t.Fatal(err)
			}
		}
	}
	mkStale(CleanDirs, filepath.Join(d, "nonexistent"))
	mkStale(CleanAgentDirs, filepath.Join(d, "agents/nonexistent"))

	if err := Clean(context.Background(), u); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(e.Out.String(), "removed") {
		t.Errorf("no removal reported:\n%s", e.Out)
	}
	for _, rel := range append(slices.Clone(CleanDirs), CleanAgentDirs...) {
		dir := filepath.Join(h, rel)
		if _, err := os.Lstat(filepath.Join(dir, "stale")); err == nil {
			t.Errorf("stale link survived in %s", dir)
		}
		if _, err := os.Lstat(filepath.Join(dir, "dangling-external")); err != nil {
			t.Errorf("external link removed in %s", dir)
		}
	}
}

func TestCleanProtectsRealFilesAndUnrelatedSymlinks(t *testing.T) {
	t.Parallel()
	d := repoRoot(t)
	u, e := setup(t, d)
	h := e.Home
	runLink(t, u)

	touch(t, filepath.Join(h, ".ssh/id_rsa"), "")
	if err := os.Symlink("/etc/hosts", filepath.Join(h, ".ssh/external_link")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(d, "nonexistent"), filepath.Join(h, ".ssh/stale_link")); err != nil {
		t.Fatal(err)
	}
	if err := Clean(context.Background(), u); err != nil {
		t.Fatal(err)
	}

	if fi, err := os.Lstat(filepath.Join(h, ".ssh/id_rsa")); err != nil || !fi.Mode().IsRegular() {
		t.Error("real file damaged")
	}
	assertLink(t, filepath.Join(h, ".ssh/external_link"), "/etc/hosts")
	if _, err := os.Lstat(filepath.Join(h, ".ssh/stale_link")); err == nil {
		t.Error("stale link survived")
	}
}

func TestLinkDoesNotMergeSettings(t *testing.T) {
	t.Parallel()
	u, e := setup(t, "")
	h := e.Home
	m := filepath.Join(h, "repo-mock")
	u.Dir = m
	touch(t, filepath.Join(m, "agents/claude/config.jsonc"), "{}\n")
	touch(t, filepath.Join(m, "agents/claude/settings.jsonc"), "{\"theme\":\"dark\"}\n")
	touch(t, filepath.Join(m, "agents/codex/config.toml"), "")
	touch(t, filepath.Join(m, "sh/.shrc"), "")
	runLink(t, u)

	for _, f := range []string{".claude/settings.json", ".codex/config.toml"} {
		if _, err := os.Stat(filepath.Join(h, f)); err == nil {
			t.Errorf("%s exists", f)
		}
	}
	if len(e.Fake.Lines()) != 0 {
		t.Errorf("commands ran: %v", e.Fake.Lines())
	}
}

// snapshot maps HOME-relative symlink paths to targets, replacing the repo prefix with "REPO".
func snapshot(t *testing.T, home, repo string) map[string]string {
	t.Helper()
	out := map[string]string{}
	err := filepath.WalkDir(home, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.Type()&fs.ModeSymlink == 0 {
			return nil
		}
		target, err := os.Readlink(p)
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(home, p)
		out[rel] = strings.Replace(target, repo, "REPO", 1)
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func TestLinkMatchesZsh(t *testing.T) {
	t.Parallel()
	zsh, err := exec.LookPath("zsh")
	if err != nil {
		t.Skip("zsh not on PATH")
	}
	repo := repoRoot(t)

	zshHome := t.TempDir()
	cmd := exec.Command(zsh, "-c", `source dot; _log() { :; }; HOME=$1; DIR=$2; _link`, "zsh", zshHome, repo)
	cmd.Dir = repo
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("zsh _link: %v\n%s", err, out)
	}

	u, e := setup(t, repo)
	runLink(t, u)

	want, got := snapshot(t, zshHome, repo), snapshot(t, e.Home, repo)
	if len(want) == 0 {
		t.Fatal("zsh created no symlinks")
	}
	for p, target := range want {
		if got[p] != target {
			t.Errorf("%s: go %q, zsh %q", p, got[p], target)
		}
	}
	for p := range got {
		if _, ok := want[p]; !ok {
			t.Errorf("%s: only in go", p)
		}
	}
}

// TestSparseCloneHasEveryRuntimePath ensures sparse clones include every linked runtime path.
func TestSparseCloneHasEveryRuntimePath(t *testing.T) {
	t.Parallel()
	root := repoRoot(t)
	clone := filepath.Join(t.TempDir(), "dotfiles")
	git := func(args ...string) {
		t.Helper()
		if out, err := exec.Command("git", args...).CombinedOutput(); err != nil {
			t.Fatalf("git %s: %v\n%s", strings.Join(args, " "), err, out)
		}
	}
	git("clone", "-q", "--no-checkout", root, clone)
	git(append([]string{"-C", clone, "sparse-checkout", "set", "--no-cone"}, repo.SparsePatterns...)...)
	git("-C", clone, "checkout", "-q")

	sparseUI, sparse := setup(t, clone)
	runLink(t, sparseUI)
	fullUI, full := setup(t, root)
	runLink(t, fullUI)

	got, want := snapshot(t, sparse.Home, clone), snapshot(t, full.Home, root)
	for p := range want {
		if _, ok := got[p]; !ok {
			t.Errorf("%s is linked from the full repo but not from a sparse clone; allowlist it in repo.SparsePatterns", p)
		}
	}
	for p := range got {
		if _, err := os.Stat(filepath.Join(sparse.Home, p)); err != nil {
			t.Errorf("%s dangles in a sparse clone: %v", p, err)
		}
	}

	// files merge and install read from the repo
	for _, p := range []string{
		"Brewfile", ".macOS", "sh/fish_plugins", "agents/claude/settings.jsonc", "agents/claude/config.jsonc",
		"agents/codex/config.toml", "orca/settings.jsonc", "rex/settings.zsh",
	} {
		if _, err := os.Stat(filepath.Join(clone, p)); err != nil {
			t.Errorf("%s missing from a sparse clone: %v", p, err)
		}
	}
}

// Pins zsh dot's handling of paths with spaces.
func TestLinkHandlesPathsWithSpaces(t *testing.T) {
	t.Parallel()
	u, e := setup(t, "")
	repo := filepath.Join(e.Home, "path with spaces")
	u.Dir = repo
	touch(t, filepath.Join(repo, "sh/.shrc"), "")
	touch(t, filepath.Join(repo, "agents/codex/config.toml"), "")
	touch(t, filepath.Join(repo, "agents/claude/settings.jsonc"), "{}\n")
	runLink(t, u)

	assertLink(t, filepath.Join(e.Home, ".bash_profile"), filepath.Join(repo, "sh/.shrc"))
}
