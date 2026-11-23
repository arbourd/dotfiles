// Package cli builds and runs dot's command tree.
package cli

import (
	"context"
	"errors"
	"fmt"
	"os"
	"slices"

	"github.com/spf13/cobra"

	"github.com/arbourd/dotfiles/internal/env"
	"github.com/arbourd/dotfiles/internal/link"
	"github.com/arbourd/dotfiles/internal/paths"
	"github.com/arbourd/dotfiles/internal/repo"
	"github.com/arbourd/dotfiles/internal/ui"
)

// usageError marks bad arguments so Main prints usage.
type usageError struct{ msg string }

func (e *usageError) Error() string { return e.msg }

func usageErrorf(format string, a ...any) error {
	return &usageError{fmt.Sprintf(format, a...)}
}

// Main runs dot with args and returns its exit code.
func Main(ctx context.Context, e *env.Env, version string, args []string) int {
	return run(ctx, e, version, DefaultTargets(), args)
}

func run(ctx context.Context, e *env.Env, version string, ts Targets, args []string) int {
	a := &app{env: e, version: version, targets: ts}
	root := a.root()
	root.SetArgs(args)
	root.SetOut(e.Stdout)
	root.SetErr(e.Stderr)

	cmd, err := root.ExecuteContextC(ctx)
	if err == nil {
		err = a.helpErr
	}
	if err == nil {
		return 0
	}
	u := a.ui()
	u.Err(err.Error())
	if _, ok := errors.AsType[*usageError](err); ok {
		fmt.Fprint(e.Stderr, cmd.UsageString())
		if t := cmd.Annotations["targets"]; t != "" {
			fmt.Fprintf(e.Stderr, "\n%s\n", t)
		}
	}
	return 1
}

type app struct {
	env     *env.Env
	version string
	targets Targets
	verbose bool
	// helpErr is set when --help names an unknown command; cobra's help func cannot return it.
	helpErr error
}

func (a *app) ui() *ui.UI {
	return ui.New(a.env, paths.DotfilesPath(a.env), a.verbose)
}

func (a *app) needRepo(u *ui.UI) error {
	if fi, err := os.Stat(u.Dir); err != nil || !fi.IsDir() {
		return fmt.Errorf("error: dotfiles not found at %s; run dot init", u.Dir)
	}
	return nil
}

// step wraps work that runs from an existing clone, warning first when it is
// not the default one.
func (a *app) step(fn func(ctx context.Context, u *ui.UI, args []string) error) func(*cobra.Command, []string) error {
	return func(cmd *cobra.Command, args []string) error {
		u := a.ui()
		if err := a.needRepo(u); err != nil {
			return err
		}
		paths.WarnLocation(u, a.env)
		return fn(cmd.Context(), u, args)
	}
}

func (a *app) root() *cobra.Command {
	root := &cobra.Command{
		Use:           "dot",
		Short:         "Sets up and maintains this machine from the dotfiles repository",
		SilenceErrors: true,
		SilenceUsage:  true,
		// a bare root would otherwise print help and exit 0
		Args: func(_ *cobra.Command, args []string) error {
			if len(args) > 0 {
				return usageErrorf("error: unknown command: %q", args[0])
			}
			return nil
		},
		RunE: func(*cobra.Command, []string) error {
			return usageErrorf("error: command required")
		},
	}
	root.PersistentFlags().BoolVarP(&a.verbose, "verbose", "v", false, "shows full output instead of spinners")
	root.SetFlagErrorFunc(func(_ *cobra.Command, err error) error {
		return usageErrorf("error: %s", err)
	})

	// cobra shows root help for `dot bogus --help` and `dot help bogus`; reject them instead.
	help := root.HelpFunc()
	root.SetHelpFunc(func(c *cobra.Command, args []string) {
		if rest := c.Flags().Args(); c == root && len(rest) > 0 {
			a.helpErr = usageErrorf("error: unknown command: %q", rest[0])
			return
		}
		help(c, args)
	})
	root.SetHelpCommand(&cobra.Command{
		Use:   "help [command]",
		Short: "Help about any command",
		RunE: func(_ *cobra.Command, args []string) error {
			cmd, rest, err := root.Find(args)
			if err != nil || (cmd == root && len(rest) > 0) {
				return usageErrorf("error: unknown command: %q", args[0])
			}
			return cmd.Help()
		},
	})

	root.AddCommand(
		&cobra.Command{
			Use:   "init",
			Short: "clones dotfiles to ~/.local/share/dotfiles as a sparse checkout",
			Args:  noArgs,
			RunE: func(cmd *cobra.Command, _ []string) error {
				return repo.Init(cmd.Context(), a.ui())
			},
		},
		&cobra.Command{
			Use:   "link",
			Short: "symlinks dotfiles and removes stale symlinks",
			Args:  noArgs,
			RunE: a.step(func(ctx context.Context, u *ui.UI, _ []string) error {
				return link.Link(ctx, u)
			}),
		},
		a.targetCommand("install", "installs all packages, or just the targets given", a.targets.Install),
		a.targetCommand("merge", "merges settings into claude, codex, orca and rex, or just the targets given", a.targets.Merge),
		&cobra.Command{
			Use:   "update",
			Short: "updates the dotfiles repository",
			Args:  noArgs,
			RunE: a.step(func(ctx context.Context, u *ui.UI, _ []string) error {
				return repo.Update(ctx, u)
			}),
		},
		&cobra.Command{
			Use:   "version",
			Short: "prints the dot version and the dotfiles commit sha",
			Args:  noArgs,
			RunE: func(cmd *cobra.Command, _ []string) error {
				u := a.ui()
				if err := a.needRepo(u); err != nil {
					return err
				}
				sha, err := repo.Head(cmd.Context(), u)
				if err != nil {
					return err
				}
				var link string
				if url := repo.URL(cmd.Context(), u); url != "" {
					link = url + "/commit/" + sha
				}
				fmt.Fprintf(a.env.Stdout, "dot %s (%s)\n", a.version, u.Hyperlink(link, sha))
				return nil
			},
		},
	)
	return root
}

func noArgs(cmd *cobra.Command, args []string) error {
	if len(args) > 0 {
		return usageErrorf("error: %s takes no arguments, got %q", cmd.Name(), args[0])
	}
	return nil
}

// targetCommand builds install or merge, running named targets in order or all targets by default.
func (a *app) targetCommand(name, short string, ts []Target) *cobra.Command {
	return &cobra.Command{
		Use:         name + " [TARGET]...",
		Short:       short,
		Long:        short + "\n\n" + targetHelp(ts),
		Annotations: map[string]string{"targets": targetHelp(ts)},
		Args: func(_ *cobra.Command, args []string) error {
			_, err := selectTargets(name, ts, args)
			return err
		},
		ValidArgsFunction: func(_ *cobra.Command, args []string, _ string) ([]cobra.Completion, cobra.ShellCompDirective) {
			var out []cobra.Completion
			for _, t := range ts {
				if !slices.Contains(args, t.Name) {
					out = append(out, cobra.CompletionWithDesc(t.Name, t.Desc))
				}
			}
			return out, cobra.ShellCompDirectiveNoFileComp
		},
		RunE: a.step(func(ctx context.Context, u *ui.UI, args []string) error {
			selected, _ := selectTargets(name, ts, args)
			if len(args) == 0 && name == "merge" {
				u.Log("Merging settings")
			}
			for _, t := range selected {
				if err := t.Run(ctx, u); err != nil {
					return err
				}
			}
			return nil
		}),
	}
}
