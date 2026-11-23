package cli

import (
	"context"
	"errors"
	"os"
	"slices"
	"strings"
	"sync"
	"testing"

	"github.com/arbourd/dotfiles/internal/env/envtest"
	"github.com/arbourd/dotfiles/internal/ui"
)

type recorder struct {
	mu   sync.Mutex
	ran  []string
	fail string // the step that fails, as "cmd name"
}

func (r *recorder) targets(cmd string, ns ...string) []Target {
	var ts []Target
	for _, n := range ns {
		ts = append(ts, Target{Name: n, Desc: n + " things", Run: func(context.Context, *ui.UI) error {
			r.mu.Lock()
			defer r.mu.Unlock()
			r.ran = append(r.ran, cmd+" "+n)
			if r.fail == cmd+" "+n {
				return errors.New(n + " failed")
			}
			return nil
		}})
	}
	return ts
}

func runDot(t *testing.T, r *recorder, args ...string) (int, *envtest.Env) {
	t.Helper()
	e := envtest.New(t)
	e.DotDir = t.TempDir()
	ts := Targets{
		Install: r.targets("install", "brew", "defaults", "fisher", "vim"),
		Merge:   r.targets("merge", "claude", "codex", "orca", "rex"),
	}
	return run(context.Background(), e.Env, "1.2.3", ts, args), e
}

func TestStepOrder(t *testing.T) {
	t.Parallel()
	tests := []struct {
		args []string
		want []string
	}{
		{[]string{"install"}, []string{"install brew", "install defaults", "install fisher", "install vim"}},
		{[]string{"merge"}, []string{"merge claude", "merge codex", "merge orca", "merge rex"}},
		{[]string{"install", "vim", "brew"}, []string{"install vim", "install brew"}},
		{[]string{"merge", "rex"}, []string{"merge rex"}},
	}
	for _, tt := range tests {
		t.Run(strings.Join(tt.args, " "), func(t *testing.T) {
			t.Parallel()
			r := &recorder{}
			if code, e := runDot(t, r, tt.args...); code != 0 {
				t.Fatalf("exit %d: %s", code, e.ErrOut)
			}
			if !slices.Equal(r.ran, tt.want) {
				t.Errorf("ran %v, want %v", r.ran, tt.want)
			}
		})
	}
}

func TestTargetsValidatedBeforeAnyRun(t *testing.T) {
	t.Parallel()
	for _, args := range [][]string{
		{"install", "brew", "bogus"},
		{"merge", ""},
		{"merge", "claude", "nope", "codex"},
	} {
		r := &recorder{}
		code, e := runDot(t, r, args...)
		if code != 1 {
			t.Errorf("%q: exit %d, want 1", args, code)
		}
		if len(r.ran) != 0 {
			t.Errorf("%q: ran %v before validating", args, r.ran)
		}
		want := `error: unknown ` + args[0] + ` target: "` + args[len(args)-1] + `"`
		if args[0] == "merge" && len(args) == 4 {
			want = `error: unknown merge target: "nope"`
		}
		if !strings.HasPrefix(e.ErrOut.String(), want+"\n") || !strings.Contains(e.ErrOut.String(), "Targets:") {
			t.Errorf("%q: stderr = %q", args, e.ErrOut)
		}
		if e.Out.Len() != 0 {
			t.Errorf("%q: stdout = %q", args, e.Out)
		}
	}
}

func TestStepFailureStopsAndExits1(t *testing.T) {
	t.Parallel()
	r := &recorder{fail: "install defaults"}
	code, e := runDot(t, r, "install")
	if code != 1 {
		t.Fatalf("exit %d, want 1", code)
	}
	if want := []string{"install brew", "install defaults"}; !slices.Equal(r.ran, want) {
		t.Errorf("ran %v, want %v", r.ran, want)
	}
	if got := e.ErrOut.String(); got != "defaults failed\n" {
		t.Errorf("stderr = %q", got)
	}
}

func TestUsageErrors(t *testing.T) {
	t.Parallel()
	tests := map[string]struct {
		args []string
		want string
	}{
		"no command":      {nil, "error: command required\n"},
		"unknown command": {[]string{"nope"}, `error: unknown command: "nope"` + "\n"},
		"unknown flag":    {[]string{"link", "--bogus"}, "error: unknown flag: --bogus\n"},
		"extra argument":  {[]string{"link", "x"}, `error: link takes no arguments, got "x"` + "\n"},
	}
	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			code, e := runDot(t, &recorder{}, tt.args...)
			if code != 1 {
				t.Errorf("exit %d, want 1", code)
			}
			if got := e.ErrOut.String(); !strings.HasPrefix(got, tt.want) || !strings.Contains(got, "Usage:") {
				t.Errorf("stderr = %q", got)
			}
		})
	}
}

func TestVerboseBeforeOrAfterCommand(t *testing.T) {
	t.Parallel()
	for _, args := range [][]string{{"-v", "merge", "rex"}, {"merge", "rex", "--verbose"}} {
		r := &recorder{}
		if code, e := runDot(t, r, args...); code != 0 {
			t.Errorf("%q: exit %d: %s", args, code, e.ErrOut)
		}
		if !slices.Equal(r.ran, []string{"merge rex"}) {
			t.Errorf("%q: ran %v", args, r.ran)
		}
	}
}

func TestMergeLogsHeaderOnlyWithoutTargets(t *testing.T) {
	t.Parallel()
	_, e := runDot(t, &recorder{}, "merge")
	if !strings.Contains(e.Out.String(), "Merging settings") {
		t.Errorf("no header: %q", e.Out)
	}
	_, e = runDot(t, &recorder{}, "merge", "codex")
	if strings.Contains(e.Out.String(), "Merging settings") {
		t.Errorf("header with a target: %q", e.Out)
	}
}

func TestRepoCommandsNeedAClone(t *testing.T) {
	t.Parallel()
	for _, cmd := range []string{"link", "install", "merge", "update", "version"} {
		r := &recorder{}
		e := envtest.New(t)
		e.DotDir = e.Home + "/missing"
		code := run(context.Background(), e.Env, "1.2.3", Targets{Install: r.targets("install", "brew"), Merge: r.targets("merge", "rex")}, []string{cmd})
		if code != 1 || !strings.Contains(e.ErrOut.String(), "run dot init") {
			t.Errorf("%s: exit %d, stderr %q", cmd, code, e.ErrOut)
		}
		if len(r.ran) != 0 {
			t.Errorf("%s: ran %v", cmd, r.ran)
		}
	}
}

func TestHelpListsTargets(t *testing.T) {
	t.Parallel()
	code, e := runDot(t, &recorder{}, "install", "--help")
	if code != 0 {
		t.Fatalf("exit %d", code)
	}
	want := "Targets:\n  brew      brew things\n  defaults  defaults things\n  fisher    fisher things\n  vim       vim things\n"
	if !strings.Contains(e.Out.String(), want) {
		t.Errorf("help = %q", e.Out)
	}
}

func TestCompletionOffersUntypedTargets(t *testing.T) {
	t.Parallel()
	code, e := runDot(t, &recorder{}, "__complete", "merge", "codex", "")
	if code != 0 {
		t.Fatalf("exit %d: %s", code, e.ErrOut)
	}
	got := e.Out.String()
	for _, want := range []string{"claude\tclaude things", "orca\torca things", "rex\trex things"} {
		if !strings.Contains(got, want) {
			t.Errorf("completion missing %q: %q", want, got)
		}
	}
	if strings.Contains(got, "codex\t") {
		t.Errorf("completion offers a typed target: %q", got)
	}
}

func TestVersion(t *testing.T) {
	t.Parallel()
	e := envtest.New(t)
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	e.DotDir = wd
	e.Fake.Real = map[string]bool{"git": true}
	if code := run(context.Background(), e.Env, "1.2.3", DefaultTargets(), []string{"version"}); code != 0 {
		t.Fatalf("exit %d: %s", code, e.ErrOut)
	}
	if got := e.Out.String(); !strings.HasPrefix(got, "dot 1.2.3 (") || !strings.HasSuffix(got, ")\n") {
		t.Errorf("version = %q", got)
	}
}

// Pins the real install and merge dispatch order from zsh dot.
func TestDefaultTargetsOrder(t *testing.T) {
	t.Parallel()
	names := func(ts []Target) []string {
		var out []string
		for _, t := range ts {
			out = append(out, t.Name)
		}
		return out
	}
	d := DefaultTargets()
	if got, want := names(d.Install), []string{"brew", "defaults", "fisher", "vim"}; !slices.Equal(got, want) {
		t.Errorf("install targets = %v, want %v", got, want)
	}
	if got, want := names(d.Merge), []string{"claude", "codex", "orca", "rex"}; !slices.Equal(got, want) {
		t.Errorf("merge targets = %v, want %v", got, want)
	}
}

// Pins zsh dot's unknown-command behavior with --help.
func TestUnknownCommandWithHelp(t *testing.T) {
	t.Parallel()
	for name, args := range map[string][]string{
		"flag after":  {"bogus", "--help"},
		"help topic":  {"help", "bogus"},
		"empty topic": {"help", ""},
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			code, e := runDot(t, &recorder{}, args...)
			if code != 1 || !strings.HasPrefix(e.ErrOut.String(), "error: unknown command") {
				t.Errorf("exit %d, stderr %q; want exit 1 and an unknown command error", code, e.ErrOut)
			}
		})
	}
}
