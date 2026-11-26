package merge

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestJSONPatch(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name, live, repo, want string
	}{
		{"nil live", "", `{"a":1}`, `{"a":1}`},
		{"blank live", " \n\t\r", `{"a":1}`, `{"a":1}`},
		{"repo wins and nested merge", `{"a":1,"o":{"x":1,"y":2}}`, `{"a":2,"o":{"y":3}}`, `{"a":2,"o":{"x":1,"y":3}}`},
		{"arrays replaced", `{"l":[1,2]}`, `{"l":[3]}`, `{"l":[3]}`},
		{"null deletes", `{"a":1,"b":2}`, `{"b":null}`, `{"a":1}`},
		{"jsonc", "{\n// c\n\"a\":1,\n}", "{/* c */ \"b\": 2,}", `{"a":1,"b":2}`},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			var live []byte
			if tt.live != "" {
				live = []byte(tt.live)
			}
			got, err := JSONPatch(t.Context(), live, []byte(tt.repo))
			if err != nil {
				t.Fatal(err)
			}
			if string(got) != tt.want {
				t.Errorf("got %s, want %s", got, tt.want)
			}
		})
	}
}

func TestJSONPatchInvalid(t *testing.T) {
	t.Parallel()
	if _, err := JSONPatch(t.Context(), nil, []byte("{\n  /* unterminated\n}")); err == nil {
		t.Fatal("want an error for invalid JSONC")
	}
}

// TestJSONPatchMatchesCLI pins compatibility with zsh dot's _json_patch via sqlite3.
func TestJSONPatchMatchesCLI(t *testing.T) {
	t.Parallel()
	sqlite3, err := exec.LookPath("sqlite3")
	if err != nil {
		t.Skip("sqlite3 not installed")
	}
	live := filepath.Join(t.TempDir(), "live.json")
	if err := os.WriteFile(live, []byte("{\n  // live\n  \"local\": {\"kept\": true},\n}\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"settings.jsonc", "config.jsonc"} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			repo, err := filepath.Abs(filepath.Join("..", "..", "agents", "claude", name))
			if err != nil {
				t.Fatal(err)
			}
			query := "SELECT json_patch(json(coalesce(nullif(trim(CAST(readfile('" + live + "') AS TEXT), ' '||char(9,10,13)), ''), '{}')), json(CAST(readfile('" + repo + "') AS TEXT)))"
			want, err := exec.Command(sqlite3, ":memory:", query).Output()
			if err != nil {
				t.Fatalf("sqlite3: %v", err)
			}

			liveData, _ := os.ReadFile(live)
			repoData, err := os.ReadFile(repo)
			if err != nil {
				t.Fatal(err)
			}
			got, err := JSONPatch(t.Context(), liveData, repoData)
			if err != nil {
				t.Fatal(err)
			}
			if string(got)+"\n" != string(want) {
				t.Errorf("modernc and sqlite3 differ:\n got %s\nwant %s", got, want)
			}
		})
	}
}
