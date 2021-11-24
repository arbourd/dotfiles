set default_user (whoami) # set default user
set fish_greeting "" # empty the greeting string
set -x SHELL /usr/local/bin/fish # let everyone know about fish

## Exports
#
set -x EDITOR vim # default editor
set -x GETPATH $HOME/src # git-get
set -x GO111MODULE auto # go mod
set -x GOPATH $HOME/go # go code home
set -x GPG_TTY (tty) # gpg
set -x HOMEBREW_EDITOR $EDITOR # brew edit
set -x PATH $GOPATH/bin $PATH # go bin
set -x PATH $HOME/.cargo/bin $PATH # rust bin
set -x PATH $HOME/.krew/bin $PATH # krew bin

## Initializations
#
if test -e /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.fish.inc
    source "/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.fish.inc"
end

direnv hook fish | source

source ~/.config/fish/private.fish
