package merge

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"

	"github.com/arbourd/dotfiles/internal/env/envtest"
	"github.com/arbourd/dotfiles/internal/ui"
)

// claudeFixture builds a UI and fake environment for Claude settings tests.
func claudeFixture(t *testing.T, repo map[string]string) (*ui.UI, *envtest.Env) {
	t.Helper()
	e := envtest.New(t)
	dir := t.TempDir()
	for name, body := range repo {
		writeFile(t, filepath.Join(dir, "agents", "claude", name), body)
	}
	return ui.New(e.Env, dir, false), e
}

func writeFile(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func readJSON(t *testing.T, path string) map[string]any {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("%s: %v", path, err)
	}
	return m
}

func jsonOf(t *testing.T, s string) map[string]any {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal([]byte(s), &m); err != nil {
		t.Fatal(err)
	}
	return m
}

func TestClaudeSettings(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name       string
		settings   string // repo settings.jsonc
		config     string // repo config.jsonc
		liveSet    *string
		liveConfig *string
		wantSet    string // expected ~/.claude/settings.json, as JSON
		wantConfig string // expected ~/.claude.json, as JSON; empty skips the check
	}{
		{
			// Repository settings merge into live settings instead of replacing the file.
			name: "deep merges over live settings",
			settings: `{
  "theme": "dark",
  "editor": { "theme": "repo-theme" },
  "ignorePatterns": ["repo-pattern"]
}
`,
			config: "{}\n",
			liveSet: new(`{
  "hooks": { "SessionStart": [{ "matcher": "", "hooks": [] }] },
  "editor": { "theme": "live-theme", "fontSize": 14 },
  "ignorePatterns": ["live-pattern"]
}
`),
			// nested objects merge with the repo winning; arrays are replaced
			wantSet: `{"hooks":{"SessionStart":[{"matcher":"","hooks":[]}]},"editor":{"theme":"repo-theme","fontSize":14},"ignorePatterns":["repo-pattern"],"theme":"dark"}`,
		},
		{
			// Empty settings are valid and the result has mode 0600.
			name:     "empty live settings",
			settings: "{\"effortLevel\": \"high\"}\n",
			config:   "{}\n",
			liveSet:  new(""),
			wantSet:  `{"effortLevel":"high"}`,
		},
		{
			name:     "missing live files",
			settings: "{\"effortLevel\": \"high\"}\n",
			config:   "{\"copyOnSelect\": false}\n",
			wantSet:  `{"effortLevel":"high"}`, wantConfig: `{"copyOnSelect":false}`,
		},
		{
			// Config merges into .claude.json while preserving app state.
			name:       "config keeps app state",
			settings:   "{}\n",
			config:     "{\"copyOnSelect\": false}\n",
			liveConfig: new("{\"copyOnSelect\": true, \"numStartups\": 5, \"projects\": {\"/x\": {\"a\": 1}}}\n"),
			wantSet:    `{}`,
			wantConfig: `{"copyOnSelect":false,"numStartups":5,"projects":{"/x":{"a":1}}}`,
		},
		{
			// JSONC comments are stripped without altering strings that resemble comments.
			name: "strips comments only",
			settings: `{
  // line comment with "quotes" and a trailing comma,
  "url": "https://example.com//path", // after a value
  /* block
     comment { "hooks": [] } */
  "glob": "src/**/*.ts",
  "escaped": "a \"// not\" comment \\",
  "block": "/* not a comment */",
  "nested": { /* inline */ "theme": "repo" }
}
`,
			config: "{}\n",
			liveSet: new(`{
  // a comment Claude Code tolerates in the live file
  "local": "kept"
}
`),
			wantSet: `{"local":"kept","url":"https://example.com//path","glob":"src/**/*.ts","escaped":"a \"// not\" comment \\","block":"/* not a comment */","nested":{"theme":"repo"}}`,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			u, e := claudeFixture(t, map[string]string{"settings.jsonc": tt.settings, "config.jsonc": tt.config})
			setPath := filepath.Join(e.Home, ".claude", "settings.json")
			configPath := filepath.Join(e.Home, ".claude.json")
			if tt.liveSet != nil {
				writeFile(t, setPath, *tt.liveSet)
			}
			if tt.liveConfig != nil {
				writeFile(t, configPath, *tt.liveConfig)
			}

			if err := claudeSettings(t.Context(), u); err != nil {
				t.Fatal(err)
			}

			checks := map[string]string{setPath: tt.wantSet, configPath: tt.wantConfig}
			for path, want := range checks {
				if want == "" {
					continue
				}
				if got := readJSON(t, path); !reflect.DeepEqual(got, jsonOf(t, want)) {
					t.Errorf("%s = %v, want %s", path, got, want)
				}
			}
			for _, path := range []string{setPath, configPath} {
				fi, err := os.Lstat(path)
				if err != nil {
					t.Fatal(err)
				}
				if fi.Mode() != 0o600 {
					t.Errorf("%s mode = %v, want -rw-------", path, fi.Mode())
				}
			}
			wantOut := "merged   agents/claude/settings.jsonc → ~/.claude/settings.json\n" +
				"merged   agents/claude/config.jsonc → ~/.claude.json\n"
			if got := e.Out.String(); got != wantOut {
				t.Errorf("output = %q, want %q", got, wantOut)
			}
		})
	}
}

// A symlinked settings file is replaced instead of written through.
func TestClaudeSettingsReplacesSymlink(t *testing.T) {
	t.Parallel()
	u, e := claudeFixture(t, map[string]string{"settings.jsonc": "{\"effortLevel\": \"high\"}\n", "config.jsonc": "{}\n"})
	target := filepath.Join(e.Home, "target.json")
	writeFile(t, target, "{\"local\": \"kept\"}\n")
	link := filepath.Join(e.Home, ".claude", "settings.json")
	if err := os.MkdirAll(filepath.Dir(link), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, link); err != nil {
		t.Fatal(err)
	}

	if err := claudeSettings(t.Context(), u); err != nil {
		t.Fatal(err)
	}

	fi, err := os.Lstat(link)
	if err != nil {
		t.Fatal(err)
	}
	if fi.Mode()&os.ModeSymlink != 0 {
		t.Error("settings.json is still a symlink")
	}
	if got, want := readJSON(t, link), jsonOf(t, `{"local":"kept","effortLevel":"high"}`); !reflect.DeepEqual(got, want) {
		t.Errorf("settings.json = %v, want %v", got, want)
	}
	if data, _ := os.ReadFile(target); string(data) != "{\"local\": \"kept\"}\n" {
		t.Errorf("symlink target was written through: %q", data)
	}
}

// Invalid JSONC leaves the live settings file untouched.
func TestClaudeSettingsFailures(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name    string
		repo    map[string]string
		wantErr string
	}{
		{
			name:    "invalid settings",
			repo:    map[string]string{"settings.jsonc": "{\n  /* unterminated\n  \"theme\": \"dark\"\n}\n", "config.jsonc": "{}\n"},
			wantErr: "Error: claude merge failed (settings.jsonc)",
		},
		{
			// If the second file fails, neither live file is written.
			name:    "invalid config",
			repo:    map[string]string{"settings.jsonc": "{\"theme\": \"light\"}\n", "config.jsonc": "{,}"},
			wantErr: "Error: claude merge failed (config.jsonc)",
		},
		{
			name:    "missing settings",
			repo:    map[string]string{"config.jsonc": "{}\n"},
			wantErr: "Error: claude merge produced nothing (settings.jsonc missing?)",
		},
		{
			name:    "missing config",
			repo:    map[string]string{"settings.jsonc": "{}\n"},
			wantErr: "Error: claude merge produced nothing (config.jsonc missing?)",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			u, e := claudeFixture(t, tt.repo)
			setPath := filepath.Join(e.Home, ".claude", "settings.json")
			configPath := filepath.Join(e.Home, ".claude.json")
			writeFile(t, setPath, "{\"local\":\"kept\"}\n")
			writeFile(t, configPath, "{\"app\":1}\n")
			e.Fake.Succeed("claude")

			err := Claude(t.Context(), u)
			if err == nil || !strings.HasPrefix(err.Error(), tt.wantErr) {
				t.Fatalf("err = %v, want prefix %q", err, tt.wantErr)
			}
			for path, want := range map[string]string{setPath: "{\"local\":\"kept\"}\n", configPath: "{\"app\":1}\n"} {
				if data, _ := os.ReadFile(path); string(data) != want {
					t.Errorf("%s changed to %q", path, data)
				}
			}
			if calls := e.Fake.Lines(); len(calls) != 0 {
				t.Errorf("ran %v after a failed merge", calls)
			}
		})
	}
}

func TestClaudeStopsWhenWriteFails(t *testing.T) {
	t.Parallel()
	u, e := claudeFixture(t, map[string]string{"settings.jsonc": "{}\n", "config.jsonc": "{}\n"})
	dir := filepath.Join(e.Home, ".claude")
	if err := os.Mkdir(dir, 0o500); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chmod(dir, 0o755) })
	e.Fake.Succeed("claude")

	if err := Claude(t.Context(), u); err == nil {
		t.Fatal("want an error when settings.json cannot be written")
	}
	if calls := e.Fake.Lines(); len(calls) != 0 {
		t.Errorf("marketplaces ran after a failed write: %v", calls)
	}
}

func TestClaudeMarketplaces(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name      string
		setup     func(*envtest.Env)
		wantCalls []string
		wantOut   string
	}{
		{
			// Every marketplace is synced.
			name:      "updates",
			setup:     func(e *envtest.Env) { e.Fake.Succeed("claude") },
			wantCalls: []string{"claude plugin marketplace update"},
			wantOut:   "ok       claude marketplaces\n",
		},
		{
			// Updates are skipped when Claude is not installed.
			name:    "not installed",
			setup:   func(*envtest.Env) {},
			wantOut: "skipped  claude marketplaces: claude not installed\n",
		},
		{
			// A failed update warns and does not stop later merges.
			name:      "update fails",
			setup:     func(e *envtest.Env) { e.Fake.Fail("claude", "") },
			wantCalls: []string{"claude plugin marketplace update"},
			wantOut:   "warn     claude marketplaces: update failed\n",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			u, e := claudeFixture(t, nil)
			tt.setup(e)
			if err := claudeMarketplaces(t.Context(), u); err != nil {
				t.Fatalf("err = %v, want nil", err)
			}
			if got := e.Fake.Lines(); !slices.Equal(got, tt.wantCalls) {
				t.Errorf("calls = %v, want %v", got, tt.wantCalls)
			}
			if got := e.Out.String(); got != tt.wantOut {
				t.Errorf("output = %q, want %q", got, tt.wantOut)
			}
		})
	}
}

// TestClaudeRealRepo checks the repository's settings and marketplace configuration.
func TestClaudeRealRepo(t *testing.T) {
	t.Parallel()
	e := envtest.New(t)
	dir, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	u := ui.New(e.Env, dir, false)
	e.Fake.Succeed("claude")

	if err := Claude(t.Context(), u); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{filepath.Join(e.Home, ".claude", "settings.json"), filepath.Join(e.Home, ".claude.json")} {
		if len(readJSON(t, path)) == 0 {
			t.Errorf("%s is empty", path)
		}
	}
	if got, want := e.Fake.Lines(), []string{"claude plugin marketplace update"}; !slices.Equal(got, want) {
		t.Errorf("calls = %v, want %v", got, want)
	}
}
