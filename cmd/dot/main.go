// Command dot sets up and maintains a macOS machine from a dotfiles repository.
package main

import (
	"context"
	"os"

	"github.com/arbourd/dotfiles/internal/cli"
	"github.com/arbourd/dotfiles/internal/env"
)

// version is set at build time with -ldflags "-X main.version=...".
var version = "dev"

func main() {
	os.Exit(cli.Main(context.Background(), env.FromOS(), version, os.Args[1:]))
}
