package merge

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"runtime"
	"testing"

	"github.com/arbourd/dotfiles/internal/env/envtest"
	"github.com/arbourd/dotfiles/internal/ui"
	"github.com/pelletier/go-toml/v2"
)

func TestCodexKeepsLiveKeysAndLayersRepoTables(t *testing.T) {
	t.Parallel()
	e := envtest.New(t)
	u := ui.New(e.Env, filepath.Join(e.Home, "repo"), false)
	repo := filepath.Join(u.Dir, "agents", "codex", "config.toml")
	live := filepath.Join(e.Home, ".codex", "config.toml")
	writeConfig(t, repo, "[marketplaces.demo]\nsource_type = \"git\"\nref = \"v2\"\n")
	writeConfig(t, live, "model = \"local-model\"\n\n[marketplaces.demo]\nref = \"v1\"\n\n[projects.\"/tmp/x\"]\ntrust_level = \"trusted\"\n")

	if err := Codex(context.Background(), u); err != nil {
		t.Fatal(err)
	}
	got := readConfig(t, live)
	if got["model"] != "local-model" || got["projects"].(map[string]any)["/tmp/x"].(map[string]any)["trust_level"] != "trusted" || got["marketplaces"].(map[string]any)["demo"].(map[string]any)["ref"] != "v2" {
		t.Fatalf("merged config = %#v", got)
	}
	if fi, err := os.Stat(live); err != nil || fi.Mode().Perm() != 0o600 {
		t.Fatalf("mode = %v, err = %v; want 0600", fi, err)
	}
	if got, want := e.Out.String(), "merged   agents/codex/config.toml → ~/.codex/config.toml\n"; got != want {
		t.Fatalf("status = %q, want %q", got, want)
	}
}

func TestCodexCreatesConfigWhenMissing(t *testing.T) {
	t.Parallel()
	e := envtest.New(t)
	u := ui.New(e.Env, filepath.Join(e.Home, "repo"), false)
	repo := filepath.Join(u.Dir, "agents", "codex", "config.toml")
	writeConfig(t, repo, "[plugins.\"a@b\"]\nenabled = true\n")

	if err := Codex(context.Background(), u); err != nil {
		t.Fatal(err)
	}
	got := readConfig(t, filepath.Join(e.Home, ".codex", "config.toml"))
	if got["plugins"].(map[string]any)["a@b"].(map[string]any)["enabled"] != true {
		t.Fatalf("merged config = %#v", got)
	}
}

func TestCodexMergesRealRepoConfigOverMachineValues(t *testing.T) {
	t.Parallel()
	e := envtest.New(t)
	_, file, _, _ := runtime.Caller(0)
	root := filepath.Join(filepath.Dir(file), "..", "..")
	u := ui.New(e.Env, root, false)
	live := filepath.Join(e.Home, ".codex", "config.toml")
	writeConfig(t, live, "machine_path = \"/Users/test\"\n[projects.\"/some/path\"]\ntrust_level = \"trusted\"\n[marketplaces.agent-skills]\nref = \"machine-version\"\n")

	if err := Codex(context.Background(), u); err != nil {
		t.Fatal(err)
	}
	got := readConfig(t, live)
	var repo map[string]any
	repoBytes, err := os.ReadFile(filepath.Join(root, "agents", "codex", "config.toml"))
	if err != nil {
		t.Fatal(err)
	}
	if err := toml.Unmarshal(repoBytes, &repo); err != nil {
		t.Fatal(err)
	}
	want := map[string]any{"machine_path": "/Users/test", "projects": map[string]any{"/some/path": map[string]any{"trust_level": "trusted"}}}
	deepMerge(want, repo)
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("merged config differs\n got: %#v\nwant: %#v", got, want)
	}
}

func TestCodexMatchesYQ(t *testing.T) {
	t.Parallel()
	yq, err := exec.LookPath("yq")
	if err != nil {
		t.Skip("yq is not installed")
	}
	e := envtest.New(t)
	u := ui.New(e.Env, filepath.Join(e.Home, "repo"), false)
	repo := filepath.Join(u.Dir, "agents", "codex", "config.toml")
	live := filepath.Join(e.Home, ".codex", "config.toml")
	writeConfig(t, repo, "[a]\nx = 2\nitems = [\"repo\"]\n")
	writeConfig(t, live, "[a]\nx = 1\ny = true\nitems = [\"live\"]\n[live_only]\nz = 3\n")
	if err := Codex(context.Background(), u); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(yq, "-p", "toml", "-o", "toml", "eval-all", ". as $i ireduce({}; . * $i)", filepath.Join(filepath.Dir(live), "config.toml"), repo)
	// Use the original live fixture because Codex already replaced the live path.
	liveInput := filepath.Join(e.Home, "live-input.toml")
	writeConfig(t, liveInput, "[a]\nx = 1\ny = true\nitems = [\"live\"]\n[live_only]\nz = 3\n")
	cmd.Args[len(cmd.Args)-2] = liveInput
	stdout, err := cmd.Output()
	if err != nil {
		t.Fatalf("yq merge: %v", err)
	}
	var yqMap map[string]any
	if err := toml.Unmarshal(stdout, &yqMap); err != nil {
		t.Fatal(err)
	}
	if got := readConfig(t, live); !reflect.DeepEqual(got, yqMap) {
		t.Fatalf("Codex output differs from yq\n got: %#v\nyq: %#v", got, yqMap)
	}
}

func writeConfig(t *testing.T, path, contents string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(contents), 0o644); err != nil {
		t.Fatal(err)
	}
}

func readConfig(t *testing.T, path string) map[string]any {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var data map[string]any
	if err := toml.Unmarshal(b, &data); err != nil {
		t.Fatal(err)
	}
	return data
}
