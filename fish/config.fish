set default_user (whoami)           # set default user
set fish_greeting ""                # empty the greeting string
set -x SHELL /usr/local/bin/fish    # let everyone know about fish

## $PATH
set -x PATH $HOME/.cargo/bin $PATH  # rust
set -x PATH $HOME/.krew/bin $PATH   # krew
set -x PATH $GOPATH/bin $PATH       # go

## Go
set -x GOPATH $HOME/go              # go code home
set -x GO111MODULE auto             # go mod

## Misc
set -x GETPATH $HOME/src            # git-get
set -x GPG_TTY (tty)                # gpg
set -x EDITOR vim                   #
set -x HOMEBREW_EDITOR vim          # brew edit

if test -e /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.fish.inc
  source "/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.fish.inc"
end

source ~/.config/fish/private.fish
