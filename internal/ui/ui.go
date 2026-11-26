// Package ui prints dot's status and spinner output, styling only terminal streams without NO_COLOR.
package ui

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"strings"
	"sync"
	"time"

	"github.com/arbourd/dotfiles/internal/env"
)

// Kind identifies a status line.
type Kind string

const (
	Linked  Kind = "linked"
	Merged  Kind = "merged"
	Updated Kind = "updated"
	OK      Kind = "ok"
	Removed Kind = "removed"
	Skipped Kind = "skipped"
	Warn    Kind = "warn"
)

// UI writes dot's output to the configured streams.
type UI struct {
	Env     *env.Env
	Dir     string // dotfiles directory, shortened to a relative path in details
	Verbose bool   // run commands directly instead of behind a spinner

	// FrameInterval is how often the spinner redraws; zero means 100ms.
	FrameInterval time.Duration
}

// New returns a UI for e.
func New(e *env.Env, dir string, verbose bool) *UI {
	return &UI{Env: e, Dir: dir, Verbose: verbose}
}

func (u *UI) color() bool { return u.Env.StdoutTTY && !u.Env.NoColor }

func (u *UI) errColor() bool { return u.Env.StderrTTY && !u.Env.NoColor }

// Tilde replaces the dotfiles directory with a relative path and the home
// directory with ~.
func (u *UI) Tilde(s string) string {
	if u.Dir != "" {
		s = strings.ReplaceAll(s, u.Dir+"/", "")
	}
	if u.Env.Home != "" {
		s = strings.ReplaceAll(s, u.Env.Home, "~")
	}
	return s
}

// Log prints a section header.
func (u *UI) Log(msg string) {
	if u.color() {
		fmt.Fprintf(u.Env.Stdout, "\n\x1b[1;38;5;67m▍ %s\x1b[0m\n\n", msg)
		return
	}
	fmt.Fprintf(u.Env.Stdout, "\n%s\n\n", msg)
}

// Status prints a one-line status.
func (u *UI) Status(kind Kind, detail string) {
	detail = u.Tilde(detail)
	if !u.color() {
		fmt.Fprintf(u.Env.Stdout, "%-8s %s\n", kind, detail)
		return
	}

	marker, color := "•", 244
	switch kind {
	case Linked, Merged, Updated, OK:
		marker, color = "✓", 108
	case Removed:
		marker, color = "–", 67
	case Skipped, Warn:
		marker, color = "!", 179
	}
	fmt.Fprintf(u.Env.Stdout, "\x1b[38;5;%dm%s\x1b[0m %-8s \x1b[38;5;244m%s\x1b[0m\n", color, marker, kind, detail)
}

// Err prints an error to stderr.
func (u *UI) Err(msg string) {
	if u.errColor() {
		fmt.Fprintf(u.Env.Stderr, "\x1b[38;5;167m✗\x1b[0m %s\n", msg)
		return
	}
	fmt.Fprintln(u.Env.Stderr, msg)
}

// Hyperlink returns a clickable link for terminals, or plain text otherwise.
func (u *UI) Hyperlink(url, text string) string {
	if url == "" || !u.color() {
		return text
	}
	return "\x1b]8;;" + url + "\x1b\\" + text + "\x1b]8;;\x1b\\"
}

// Spin shows fn's output only on failure when styling is enabled and Verbose is false.
// It reports success in either mode.
func (u *UI) Spin(title string, fn func(stdout, stderr io.Writer) error) error {
	if u.color() && !u.Verbose {
		var out bytes.Buffer
		w := &syncWriter{w: &out}
		stop := u.spinner(title)
		err := fn(w, w)
		stop()
		if err != nil {
			u.Env.Stderr.Write(out.Bytes())
			return err
		}
	} else {
		if err := fn(u.Env.Stdout, u.Env.Stderr); err != nil {
			return err
		}
		if u.Verbose {
			fmt.Fprintln(u.Env.Stdout)
		}
	}
	u.Status(OK, title)
	return nil
}

// SpinCmd runs c through Spin.
func (u *UI) SpinCmd(ctx context.Context, title string, c env.Cmd) error {
	return u.Spin(title, func(stdout, stderr io.Writer) error {
		c.Stdout, c.Stderr = stdout, stderr
		return u.Env.Runner.Run(ctx, c)
	})
}

var frames = []string{"⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"}

// spinner draws frames until stop is called, then clears the line.
func (u *UI) spinner(title string) (stop func()) {
	interval := u.FrameInterval
	if interval == 0 {
		interval = 100 * time.Millisecond
	}
	done := make(chan struct{})
	var wg sync.WaitGroup
	wg.Go(func() {
		t := time.NewTicker(interval)
		defer t.Stop()
		for i := 0; ; i++ {
			fmt.Fprintf(u.Env.Stdout, "\r\x1b[K\x1b[38;5;212m%s\x1b[0m %s", frames[i%len(frames)], title)
			select {
			case <-done:
				fmt.Fprint(u.Env.Stdout, "\r\x1b[K")
				return
			case <-t.C:
			}
		}
	})
	return func() {
		close(done)
		wg.Wait()
	}
}

// syncWriter serializes writes from stdout and stderr goroutines.
type syncWriter struct {
	mu sync.Mutex
	w  io.Writer
}

func (s *syncWriter) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.w.Write(p)
}
