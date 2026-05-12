set default_user (whoami)
set fish_greeting ""

## Exports
#
set -x SHELL /opt/homebrew/bin/fish
set -x EDITOR vim
set -x PATH $HOME/.local/bin $PATH
set -x PATH $HOME/go/bin $PATH
set -x PATH $HOME/.cargo/bin $PATH

## Initializations
#
if test -e /opt/homebrew/bin/brew
    eval (/opt/homebrew/bin/brew shellenv)
end

if test -e /opt/homebrew/bin/zoxide
    zoxide init fish | source
end

source ~/.config/fish/private.fish
