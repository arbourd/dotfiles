# Set default user
set default_user dylan

# Load nvm with nvm-wrapper
source ~/.config/fish/nvm-wrapper/nvm.fish

# Set path for rbenv
set PATH $HOME/.rbenv/bin $PATH
set PATH $HOME/.rbenv/shims $PATH
rbenv rehash >/dev/null ^&1

# Set GOPATH for go
set -x GOPATH $HOME/dev/go

# Set $SHELL env var for docker-machine
set -x SHELL fish
eval (docker-machine env)

# Empty the greeting string
set fish_greeting ""

# Path to your oh-my-fish.
set fish_path $HOME/.oh-my-fish

# Theme
set fish_theme cmorrell.com

# All built-in plugins can be found at ~/.oh-my-fish/plugins/
# Custom plugins may be added to ~/.oh-my-fish/custom/plugins/
# Enable plugins by adding their name separated by a space to the line below.
set fish_plugins theme

# Path to your custom folder (default path is ~/.oh-my-fish/custom)
#set fish_custom $HOME/dotfiles/oh-my-fish

# Load oh-my-fish configuration.
. $fish_path/oh-my-fish.fish
