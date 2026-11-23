// Package env holds dot's process state and the interfaces tests fake.
package env

import (
	"context"
	"io"
	"os"
	"os/exec"

	"golang.org/x/term"
)

// Env snapshots the process state dot uses.
type Env struct {
	Home        string // $HOME
	DotDir      string // $DOT_DIR, overrides where the dotfiles live
	XDGDataHome string // $XDG_DATA_HOME
	TermProgram string // $TERM_PROGRAM
	NoColor     bool   // $NO_COLOR is set and non-empty

	Stdout    io.Writer
	Stderr    io.Writer
	StdoutTTY bool
	StderrTTY bool

	Runner Runner
}

// FromOS builds an Env from the current process.
func FromOS() *Env {
	return &Env{
		Home:        os.Getenv("HOME"),
		DotDir:      os.Getenv("DOT_DIR"),
		XDGDataHome: os.Getenv("XDG_DATA_HOME"),
		TermProgram: os.Getenv("TERM_PROGRAM"),
		NoColor:     os.Getenv("NO_COLOR") != "",
		Stdout:      os.Stdout,
		Stderr:      os.Stderr,
		StdoutTTY:   term.IsTerminal(int(os.Stdout.Fd())),
		StderrTTY:   term.IsTerminal(int(os.Stderr.Fd())),
		Runner:      ExecRunner{},
	}
}

// Cmd describes an external command.
type Cmd struct {
	Name   string
	Args   []string
	Dir    string    // working directory; empty means the current one
	Env    []string  // extra KEY=VALUE pairs appended to the process environment
	Stdin  io.Reader // nil means no input
	Stdout io.Writer // nil discards
	Stderr io.Writer // nil discards
}

// Runner runs external commands and finds them on PATH.
type Runner interface {
	Run(ctx context.Context, c Cmd) error
	LookPath(name string) (string, error)
}

// ExecRunner runs commands with os/exec.
type ExecRunner struct{}

func (ExecRunner) Run(ctx context.Context, c Cmd) error {
	cmd := exec.CommandContext(ctx, c.Name, c.Args...)
	cmd.Dir = c.Dir
	if len(c.Env) > 0 {
		cmd.Env = append(os.Environ(), c.Env...)
	}
	cmd.Stdin = c.Stdin
	cmd.Stdout = c.Stdout
	cmd.Stderr = c.Stderr
	return cmd.Run()
}

func (ExecRunner) LookPath(name string) (string, error) {
	return exec.LookPath(name)
}

// Has reports whether name is on PATH.
func Has(r Runner, name string) bool {
	_, err := r.LookPath(name)
	return err == nil
}
