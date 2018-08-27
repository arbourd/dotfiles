# Set default user
set default_user (whoami)

# Set GPG TTY
set -x GPG_TTY (tty)

# Go
set -x GOPATH $HOME
set -x PATH $GOPATH/bin $PATH
set -x GO111MODULE on

# Rust
set -x PATH $HOME/.cargo/bin $PATH

set -x HOMEBREW_EDITOR vim

# Set $SHELL env var for fish
set -x SHELL fish

# Empty the greeting string
set fish_greeting ""

source ~/.config/fish/private.fish
