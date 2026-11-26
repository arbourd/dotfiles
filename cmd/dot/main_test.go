package main

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

var bin string

func TestMain(m *testing.M) {
	dir, err := os.MkdirTemp("", "dot-test-")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	bin = filepath.Join(dir, "dot")
	if out, err := exec.Command("go", "build", "-o", bin, ".").CombinedOutput(); err != nil {
		fmt.Fprintf(os.Stderr, "build dot: %v\n%s", err, out)
		os.Exit(1)
	}
	code := m.Run()
	os.RemoveAll(dir)
	os.Exit(code)
}

type result struct {
	code           int
	stdout, stderr string
}

// dot runs the binary with a temp HOME and optional environment overrides.
func dot(t *testing.T, env []string, args ...string) result {
	t.Helper()
	home := t.TempDir()
	cmd := exec.Command(bin, args...)
	cmd.Env = append([]string{"HOME=" + home, "PATH=" + os.Getenv("PATH")}, env...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	err := cmd.Run()
	code := 0
	if ee, ok := errors.AsType[*exec.ExitError](err); ok {
		code = ee.ExitCode()
	} else if err != nil {
		t.Fatal(err)
	}
	return result{code, stdout.String(), stderr.String()}
}

func TestErrorsGoToStderrWithExit1(t *testing.T) {
	t.Parallel()
	tests := map[string][]string{
		"no command":      nil,
		"unknown command": {"nope"},
		"unknown target":  {"install", "bogus"},
		"empty target":    {"merge", ""},
		"missing clone":   {"link"},
	}
	for name, args := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			r := dot(t, nil, args...)
			if r.code != 1 {
				t.Errorf("exit %d, want 1", r.code)
			}
			if r.stdout != "" {
				t.Errorf("stdout = %q", r.stdout)
			}
			if !strings.HasPrefix(r.stderr, "error: ") {
				t.Errorf("stderr = %q", r.stderr)
			}
		})
	}
}

func TestHelpExits0OnStdout(t *testing.T) {
	t.Parallel()
	for _, args := range [][]string{{"--help"}, {"-h"}, {"help"}, {"install", "--help"}, {"help", "merge"}} {
		r := dot(t, nil, args...)
		if r.code != 0 || r.stderr != "" || !strings.Contains(r.stdout, "Usage:") {
			t.Errorf("%q: exit %d, stdout %q, stderr %q", args, r.code, r.stdout, r.stderr)
		}
	}
}

func TestCompletionScripts(t *testing.T) {
	t.Parallel()
	for _, shell := range []string{"fish", "bash", "zsh"} {
		r := dot(t, nil, "completion", shell)
		if r.code != 0 || !strings.Contains(r.stdout, "dot") {
			t.Errorf("%s: exit %d, stderr %q", shell, r.code, r.stderr)
		}
	}
	r := dot(t, nil, "__complete", "install", "")
	for _, target := range []string{"brew", "defaults", "fisher", "vim"} {
		if !strings.Contains(r.stdout, target+"\t") {
			t.Errorf("install completion missing %s: %q", target, r.stdout)
		}
	}
}

func TestVersionFromRepo(t *testing.T) {
	t.Parallel()
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	r := dot(t, []string{"DOT_DIR=" + filepath.Join(wd, "..", "..")}, "version")
	if r.code != 0 || !strings.HasPrefix(r.stdout, "dot dev (") {
		t.Errorf("exit %d, stdout %q, stderr %q", r.code, r.stdout, r.stderr)
	}
}
