# Set default user
set default_user dylan

# Set path for rbenv
set PATH $HOME/.rbenv/bin $PATH
set PATH $HOME/.rbenv/shims $PATH
rbenv rehash >/dev/null ^&1

# Set path for pyenv
set PATH $HOME/.pyenv/shims $PATH

# Set GOPATH for go
set -x GOPATH $HOME/dev/go

# Set $SHELL env var for docker-machine
set -x SHELL fish

# Empty the greeting string
set fish_greeting ""
