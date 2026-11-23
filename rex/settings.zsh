#!/usr/bin/env zsh
set -e

# Default: unset
defaults write com.superlogical.rex Workspace.appearance -string dark

# Default: unset
defaults write com.superlogical.rex Workspace.interfaceStyle -string useTheme

# Default: unset
defaults write com.superlogical.rex Workspace.paneDensity -string comfortable

# Default: unset
defaults write com.superlogical.rex Workspace.sidebarPosition -string left

# Default: unset
defaults write com.superlogical.rex Workspace.tabStyle -string vertical

# Default: unset
defaults write com.superlogical.rex Workspace.terminalCursorStyle -string underline

# Default: unset
defaults write com.superlogical.rex Workspace.terminalFontName -string "Source Code Pro for Powerline"

# Default: unset
defaults write com.superlogical.rex Workspace.terminalFontPointSize -float 14

# Default: ""
defaults write com.superlogical.rex Workspace.terminalStartupCommand -string /opt/homebrew/bin/fish
