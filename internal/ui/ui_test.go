package ui

import (
	"context"
	"errors"
	"io"
	"strings"
	"testing"
	"time"

	"github.com/arbourd/dotfiles/internal/env"
	"github.com/arbourd/dotfiles/internal/env/envtest"
)

func newUI(t *testing.T, tty, noColor, verbose bool) (*UI, *envtest.Env) {
	t.Helper()
	e := envtest.New(t)
	e.StdoutTTY, e.StderrTTY, e.NoColor = tty, tty, noColor
	u := New(e.Env, "/repo", verbose)
	u.FrameInterval = time.Millisecond
	return u, e
}

func TestStatusPlain(t *testing.T) {
	t.Parallel()
	u, e := newUI(t, false, false, false)
	u.Status(Linked, e.Home+"/.zshrc → /repo/sh/.shrc")
	if got, want := e.Out.String(), "linked   ~/.zshrc → sh/.shrc\n"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestStatusColor(t *testing.T) {
	t.Parallel()
	tests := []struct {
		kind   Kind
		marker string
		color  string
	}{
		{Linked, "✓", "108"}, {Merged, "✓", "108"}, {Updated, "✓", "108"}, {OK, "✓", "108"},
		{Removed, "–", "67"},
		{Skipped, "!", "179"}, {Warn, "!", "179"},
		{"other", "•", "244"},
	}
	for _, tt := range tests {
		t.Run(string(tt.kind), func(t *testing.T) {
			t.Parallel()
			u, e := newUI(t, true, false, false)
			u.Status(tt.kind, "detail")
			want := "\x1b[38;5;" + tt.color + "m" + tt.marker + "\x1b[0m " +
				padRight(string(tt.kind), 8) + " \x1b[38;5;244mdetail\x1b[0m\n"
			if got := e.Out.String(); got != want {
				t.Errorf("got %q, want %q", got, want)
			}
		})
	}
}

func padRight(s string, n int) string {
	for len(s) < n {
		s += " "
	}
	return s
}

func TestNoColorDisablesStyling(t *testing.T) {
	t.Parallel()
	u, e := newUI(t, true, true, false)
	u.Log("Header")
	u.Status(OK, "fine")
	u.Err("bad")
	if got := e.Out.String() + e.ErrOut.String(); strings.Contains(got, "\x1b") {
		t.Errorf("styled output with NO_COLOR: %q", got)
	}
	if got := u.Hyperlink("https://x", "t"); got != "t" {
		t.Errorf("hyperlink with NO_COLOR: %q", got)
	}
}

func TestErr(t *testing.T) {
	t.Parallel()
	u, e := newUI(t, false, false, false)
	u.Err("error: nope")
	if got := e.ErrOut.String(); got != "error: nope\n" {
		t.Errorf("plain err: %q", got)
	}
	u, e = newUI(t, true, false, false)
	u.Err("error: nope")
	if got := e.ErrOut.String(); got != "\x1b[38;5;167m✗\x1b[0m error: nope\n" {
		t.Errorf("color err: %q", got)
	}
}

func TestHyperlink(t *testing.T) {
	t.Parallel()
	u, _ := newUI(t, true, false, false)
	if got, want := u.Hyperlink("https://x/c/1", "1"), "\x1b]8;;https://x/c/1\x1b\\1\x1b]8;;\x1b\\"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
	if got := u.Hyperlink("", "1"); got != "1" {
		t.Errorf("empty url: %q", got)
	}
	u, _ = newUI(t, false, false, false)
	if got := u.Hyperlink("https://x", "1"); got != "1" {
		t.Errorf("no tty: %q", got)
	}
}

func TestSpinOnTTYHidesOutputOnSuccess(t *testing.T) {
	t.Parallel()
	u, e := newUI(t, true, false, false)
	err := u.Spin("thing", func(stdout, _ io.Writer) error {
		io.WriteString(stdout, "noisy")
		time.Sleep(5 * time.Millisecond)
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	out := e.Out.String()
	if strings.Contains(out, "noisy") {
		t.Errorf("output shown on success: %q", out)
	}
	if !strings.Contains(out, "⣾") || !strings.HasSuffix(out, "\x1b[38;5;244mthing\x1b[0m\n") {
		t.Errorf("no spinner or ok line: %q", out)
	}
}

func TestSpinOnTTYShowsOutputAndFailsOnError(t *testing.T) {
	t.Parallel()
	u, e := newUI(t, true, false, false)
	boom := errors.New("boom")
	err := u.Spin("thing", func(_, stderr io.Writer) error {
		io.WriteString(stderr, "why it failed")
		return boom
	})
	if !errors.Is(err, boom) {
		t.Fatalf("err = %v, want boom", err)
	}
	if got := e.ErrOut.String(); got != "why it failed" {
		t.Errorf("stderr = %q", got)
	}
	if strings.Contains(e.Out.String(), "ok") {
		t.Errorf("ok reported on failure: %q", e.Out.String())
	}
}

func TestSpinFallsBackWithoutTTY(t *testing.T) {
	t.Parallel()
	u, e := newUI(t, false, false, false)
	err := u.Spin("thing", func(stdout, _ io.Writer) error {
		io.WriteString(stdout, "direct\n")
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if got, want := e.Out.String(), "direct\nok       thing\n"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

func TestSpinPropagatesFailureWithoutTTY(t *testing.T) {
	t.Parallel()
	u, e := newUI(t, false, false, false)
	if err := u.Spin("thing", func(io.Writer, io.Writer) error { return errors.New("x") }); err == nil {
		t.Fatal("want error")
	}
	if e.Out.Len() != 0 {
		t.Errorf("ok reported on failure: %q", e.Out.String())
	}
}

func TestSpinBypassesSpinnerWithVerbose(t *testing.T) {
	t.Parallel()
	u, e := newUI(t, true, false, true)
	err := u.Spin("thing", func(stdout, _ io.Writer) error {
		io.WriteString(stdout, "shown\n")
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	out := e.Out.String()
	if strings.Contains(out, "⣾") || !strings.HasPrefix(out, "shown\n\n") {
		t.Errorf("verbose output = %q", out)
	}
}

func TestSpinCmd(t *testing.T) {
	t.Parallel()
	u, e := newUI(t, false, false, false)
	e.Fake.Handle("brew", func(c env.Cmd) error {
		io.WriteString(c.Stdout, "bundled\n")
		return nil
	})
	if err := u.SpinCmd(context.Background(), "homebrew", env.Cmd{Name: "brew", Args: []string{"bundle"}}); err != nil {
		t.Fatal(err)
	}
	if got := e.Fake.Lines(); len(got) != 1 || got[0] != "brew bundle" {
		t.Errorf("calls = %v", got)
	}
	if got, want := e.Out.String(), "bundled\nok       homebrew\n"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}

// Pins zsh dot's rule that NO_COLOR disables spinner styling on a tty.
func TestNoColorDisablesSpinnerOnTTY(t *testing.T) {
	t.Parallel()
	u, e := newUI(t, true, true, false)
	err := u.Spin("title", func(stdout, _ io.Writer) error {
		io.WriteString(stdout, "direct\n")
		time.Sleep(5 * time.Millisecond)
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if got, want := e.Out.String(), "direct\nok       title\n"; got != want {
		t.Errorf("got %q, want %q", got, want)
	}
}
