set default_user (whoami) # set default user
set fish_greeting "" # empty the greeting string
set -x SHELL /opt/homebrew/bin/fish # let everyone know about fish

## Exports
#
set -x EDITOR vim # default editor
set -x GOPATH $HOME/go # go code home
set -x GPG_TTY (tty) # gpg
set -x HOMEBREW_EDITOR $EDITOR # brew edit
set -x PATH $GOPATH/bin $PATH # go bin
set -x PATH $HOME/.cargo/bin $PATH # rust bin

# kubectl and GKE for < 1.25
set -x USE_GKE_GCLOUD_AUTH_PLUGIN True

## Initializations
#
if test -e /opt/homebrew/bin/brew
    eval (/opt/homebrew/bin/brew shellenv)
end

if test -e /opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.fish.inc
    source "/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.fish.inc"
end

if test -e /opt/homebrew/bin/pyenv
    pyenv init - | source
end

if test -e /opt/homebrew/bin/swiftenv
    eval (swiftenv init -)
end

source ~/.config/fish/private.fish
