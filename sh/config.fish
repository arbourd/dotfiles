set default_user (whoami) # set default user
set fish_greeting "" # empty the greeting string
set -x SHELL /opt/homebrew/bin/fish # let everyone know about fish

## Exports
#
set -x EDITOR vim # default editor
set -x GETPATH $HOME/src # git-get
set -x GOPATH $HOME/go # go code home
set -x GPG_TTY (tty) # gpg
set -x HOMEBREW_EDITOR $EDITOR # brew edit
set -x PATH $GOPATH/bin $PATH # go bin
set -x PATH $HOME/.cargo/bin $PATH # rust bin

## Initializations
#
if test -e /opt/homebrew/bin/brew
    eval (/opt/homebrew/bin/brew shellenv)
end

if test -e /opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.fish.inc
    source "/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.fish.inc"
end

source ~/.config/fish/private.fish
