package merge

import (
	"errors"
	"io"
	"path/filepath"
	"testing"

	"github.com/arbourd/dotfiles/internal/env"
	"github.com/arbourd/dotfiles/internal/env/envtest"
	"github.com/arbourd/dotfiles/internal/ui"
)

func TestRexSkipsWithoutPreferences(t *testing.T) {
	t.Parallel()
	e := envtest.New(t)
	e.Fake.Fail("defaults", "")
	u := ui.New(e.Env, t.TempDir(), false)
	if err := Rex(t.Context(), u); err != nil {
		t.Fatal(err)
	}
	want := "skipped  rex settings: no preferences yet, launch Rex once and rerun\n"
	if got := e.Out.String(); got != want {
		t.Errorf("output = %q, want %q", got, want)
	}
	if lines := e.Fake.Lines(); len(lines) != 1 {
		t.Errorf("ran %v, want only defaults read", lines)
	}
}

func TestRexRunsSettingsScript(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	script := filepath.Join(dir, "rex", "settings.zsh")
	tests := []struct {
		name    string
		fail    bool
		wantOut string
	}{
		{"merged", false, "merged   rex settings → com.superlogical.rex\n"},
		{"script fails", true, ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			t.Parallel()
			e := envtest.New(t)
			e.Fake.Succeed("defaults")
			e.Fake.Handle(script, func(c env.Cmd) error {
				io.WriteString(c.Stdout, "ran\n")
				if tt.fail {
					return errors.New("exit status 1")
				}
				return nil
			})
			u := ui.New(e.Env, dir, false)
			err := Rex(t.Context(), u)
			if (err != nil) != tt.fail {
				t.Fatalf("err = %v, fail = %v", err, tt.fail)
			}
			if got := e.Out.String(); got != "ran\n"+tt.wantOut {
				t.Errorf("output = %q", got)
			}
		})
	}
}
