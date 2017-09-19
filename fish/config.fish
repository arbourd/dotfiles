# Set default user
set default_user (whoami)

# Set GPG TTY
set -x GPG_TTY (tty)

# Set GOPATH for go
set -x GOPATH $HOME/go
set -x PATH $GOPATH/bin $PATH

set -x HOMEBREW_EDITOR vim

# Set $SHELL env var for fish
set -x SHELL fish

# Empty the greeting string
set fish_greeting ""

source ~/.config/fish/private.fish
