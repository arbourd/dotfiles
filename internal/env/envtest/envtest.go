// Package envtest provides test doubles for env.
package envtest

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"os/exec"
	"strings"
	"sync"
	"testing"

	"github.com/arbourd/dotfiles/internal/env"
)

// Env is an env.Env with captured output and a fake Runner.
type Env struct {
	*env.Env
	Out    *bytes.Buffer
	ErrOut *bytes.Buffer
	Fake   *Runner
}

// New returns an Env with a temporary HOME, no terminals, and no commands.
func New(t testing.TB) *Env {
	t.Helper()
	out, errOut := &bytes.Buffer{}, &bytes.Buffer{}
	fake := &Runner{}
	return &Env{
		Env: &env.Env{
			Home:   t.TempDir(),
			Stdout: out,
			Stderr: errOut,
			Runner: fake,
		},
		Out:    out,
		ErrOut: errOut,
		Fake:   fake,
	}
}

// Handler handles a command; c.Stdout and c.Stderr are always non-nil.
type Handler func(c env.Cmd) error

// Runner records commands and dispatches them by name. Unhandled commands fail.
type Runner struct {
	mu       sync.Mutex
	handlers map[string]Handler
	calls    []env.Cmd
	// Real lets the named commands run for real, for tests that need git.
	Real map[string]bool
}

// Handle registers h for name, which also makes LookPath find it.
func (r *Runner) Handle(name string, h Handler) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.handlers == nil {
		r.handlers = map[string]Handler{}
	}
	r.handlers[name] = h
}

// Succeed makes name a command that succeeds silently.
func (r *Runner) Succeed(name string) {
	r.Handle(name, func(env.Cmd) error { return nil })
}

// Fail makes name a command that prints output to stderr and fails.
func (r *Runner) Fail(name, output string) {
	r.Handle(name, func(c env.Cmd) error {
		io.WriteString(c.Stderr, output)
		return fmt.Errorf("%s: exit status 1", name)
	})
}

func (r *Runner) Run(ctx context.Context, c env.Cmd) error {
	r.mu.Lock()
	r.calls = append(r.calls, c)
	h, ok := r.handlers[c.Name]
	real := r.Real[c.Name]
	r.mu.Unlock()

	if real {
		return env.ExecRunner{}.Run(ctx, c)
	}
	if !ok {
		return &exec.Error{Name: c.Name, Err: exec.ErrNotFound}
	}
	if c.Stdout == nil {
		c.Stdout = io.Discard
	}
	if c.Stderr == nil {
		c.Stderr = io.Discard
	}
	return h(c)
}

func (r *Runner) LookPath(name string) (string, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if _, ok := r.handlers[name]; ok {
		return "/fake/bin/" + name, nil
	}
	if r.Real[name] {
		return exec.LookPath(name)
	}
	return "", &exec.Error{Name: name, Err: exec.ErrNotFound}
}

// Calls returns every recorded command.
func (r *Runner) Calls() []env.Cmd {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]env.Cmd(nil), r.calls...)
}

// Lines returns each recorded command as "name arg...".
func (r *Runner) Lines() []string {
	var out []string
	for _, c := range r.Calls() {
		out = append(out, strings.Join(append([]string{c.Name}, c.Args...), " "))
	}
	return out
}
