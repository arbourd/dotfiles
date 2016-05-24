# Set default user
set default_user dylan

# Virtualfish with auto activation
eval (python -m virtualfish auto_activation)

# Set GOPATH for go
set -x GOPATH $HOME/dev/go

# Set $SHELL env var for docker-machine
set -x SHELL fish

# Empty the greeting string
set fish_greeting ""
