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

# Empty the greeting string
set fish_greeting ""

# Path to Oh My Fish Install
set -gx OMF_PATH /Users/dylan/.local/share/omf

# Customize Oh My Fish configuration path.
# #set -gx OMF_CONFIG /Users/dylan/.config/omf
#
# # Load oh-my-fish configuration.
source $OMF_PATH/init.fish
