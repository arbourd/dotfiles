package merge

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/arbourd/dotfiles/internal/env/envtest"
	"github.com/arbourd/dotfiles/internal/ui"
)

const orcaInitial = `{"terminalScopeHistoryByWorktree":true,"other":1}`

// orcaFixture builds a settings database and UI; pgrep fails unless overridden.
func orcaFixture(t *testing.T, dir string) (*ui.UI, *envtest.Env, string) {
	t.Helper()
	e := envtest.New(t)
	e.Fake.Fail("pgrep", "")
	db := filepath.Join(e.Home, "Library", "Application Support", "orca", "profiles", "local-default", "profile-state.db")
	if err := os.MkdirAll(filepath.Dir(db), 0o755); err != nil {
		t.Fatal(err)
	}
	conn, err := openDB(db)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	if _, err := conn.Exec(`CREATE TABLE profile_state_documents (domain TEXT PRIMARY KEY, payload TEXT, content_hash TEXT);
		INSERT INTO profile_state_documents VALUES ('settings', '` + orcaInitial + `', 'stale')`); err != nil {
		t.Fatal(err)
	}
	return ui.New(e.Env, dir, false), e, db
}

func orcaRow(t *testing.T, db string) (payload, hash string) {
	t.Helper()
	conn, err := openDB(db)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	if err := conn.QueryRow(`SELECT payload, content_hash FROM profile_state_documents WHERE domain='settings'`).Scan(&payload, &hash); err != nil {
		t.Fatal(err)
	}
	return
}

func TestOrcaMerge(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name    string
		dirName string
		repo    string
		initial string // overrides the db payload when set
		want    map[string]any
	}{
		{
			name:    "applies values and updates content_hash",
			dirName: "dotfiles",
			repo:    "// comment\n{\"terminalScopeHistoryByWorktree\": false,}\n",
			want:    map[string]any{"terminalScopeHistoryByWorktree": false, "other": float64(1)},
		},
		{
			name:    "handles a quote in the dotfiles path",
			dirName: "it's dotfiles",
			repo:    `{"terminalScopeHistoryByWorktree": false}`,
			want:    map[string]any{"terminalScopeHistoryByWorktree": false, "other": float64(1)},
		},
		{
			name:    "deletes top-level and nested keys the repo sets to null",
			dirName: "dotfiles",
			repo:    `{"gone": null, "nested": {"gone": null, "set": 2}, "absent": {"gone": null, "set": 4}}`,
			initial: `{"gone":{"x":1},"nested":{"gone":1,"keep":3},"other":1}`,
			want: map[string]any{
				"absent": map[string]any{"set": float64(4)},
				"nested": map[string]any{"keep": float64(3), "set": float64(2)},
				"other":  float64(1),
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			dir := filepath.Join(t.TempDir(), tt.dirName)
			writeFile(t, filepath.Join(dir, "orca", "settings.jsonc"), tt.repo)
			u, e, db := orcaFixture(t, dir)
			if tt.initial != "" {
				conn, err := openDB(db)
				if err != nil {
					t.Fatal(err)
				}
				_, err = conn.Exec(`UPDATE profile_state_documents SET payload = ?`, tt.initial)
				conn.Close()
				if err != nil {
					t.Fatal(err)
				}
			}

			if err := Orca(t.Context(), u); err != nil {
				t.Fatal(err)
			}
			if !strings.HasPrefix(e.Out.String(), "merged   orca settings") {
				t.Errorf("output = %q", e.Out.String())
			}
			payload, hash := orcaRow(t, db)
			sum := sha256.Sum256([]byte(payload))
			if hash != hex.EncodeToString(sum[:]) {
				t.Errorf("content_hash = %s, want sha256 of payload", hash)
			}
			got := jsonOf(t, payload)
			if len(got) != len(tt.want) {
				t.Errorf("payload = %s, want %v", payload, tt.want)
			}
			for k, v := range tt.want {
				if !jsonEqual(got[k], v) {
					t.Errorf("payload[%s] = %v, want %v", k, got[k], v)
				}
			}
		})
	}
}

func jsonEqual(a, b any) bool {
	am, aok := a.(map[string]any)
	bm, bok := b.(map[string]any)
	if aok != bok {
		return false
	}
	if !aok {
		return a == b
	}
	if len(am) != len(bm) {
		return false
	}
	for k, v := range am {
		if !jsonEqual(v, bm[k]) {
			return false
		}
	}
	return true
}

func TestOrcaMissingSettingsFile(t *testing.T) {
	t.Parallel()
	u, _, db := orcaFixture(t, t.TempDir())
	err := Orca(t.Context(), u)
	if err == nil || !strings.Contains(err.Error(), "produced no payload") {
		t.Fatalf("err = %v, want produced no payload", err)
	}
	payload, hash := orcaRow(t, db)
	if hash != "stale" || payload != orcaInitial {
		t.Errorf("db changed: %s %s", payload, hash)
	}
}

func TestOrcaSkips(t *testing.T) {
	t.Parallel()
	tests := []struct {
		name  string
		setup func(e *envtest.Env, db string)
		want  string
	}{
		{
			name:  "Orca is running",
			setup: func(e *envtest.Env, _ string) { e.Fake.Succeed("pgrep") },
			want:  "skipped  orca settings: quit Orca and rerun\n",
		},
		{
			name:  "run inside Orca",
			setup: func(e *envtest.Env, _ string) { e.TermProgram = "Orca" },
			want:  "skipped  orca settings: run from a terminal outside Orca\n",
		},
		{
			name:  "db is missing",
			setup: func(_ *envtest.Env, db string) { os.Remove(db) },
			want:  "skipped  orca settings: ~/Library/Application Support/orca/profiles/local-default/profile-state.db not found\n",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			dir := t.TempDir()
			writeFile(t, filepath.Join(dir, "orca", "settings.jsonc"), `{"other": 2}`)
			u, e, db := orcaFixture(t, dir)
			tt.setup(e, db)
			if err := Orca(t.Context(), u); err != nil {
				t.Fatal(err)
			}
			if got := e.Out.String(); got != tt.want {
				t.Errorf("output = %q, want %q", got, tt.want)
			}
			if _, err := os.Stat(db); err != nil {
				return // db removed on purpose
			}
			if _, hash := orcaRow(t, db); hash != "stale" {
				t.Errorf("content_hash = %q, want stale", hash)
			}
		})
	}
}
