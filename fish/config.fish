# Set default user
set default_user dylan

# Set GOPATH for go
set -x GOPATH $HOME/go
set -x PATH $GOPATH/bin $PATH

# Set $SHELL env var for fish
set -x SHELL fish

# Empty the greeting string
set fish_greeting ""
