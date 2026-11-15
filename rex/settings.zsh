#!/usr/bin/env zsh
set -e

# Default: not documented.
defaults write com.superlogical.rex Workspace.tabStyle -string vertical

# Default: not documented.
defaults write com.superlogical.rex Workspace.sidebarPosition -string left

# Default: not documented.
defaults write com.superlogical.rex Workspace.paneDensity -string comfortable

# Default: not documented. Fades surfaces, content, both, or neither.
defaults write com.superlogical.rex Workspace.inactivePaneFadeMode -string both

# Default: not documented.
defaults write com.superlogical.rex Workspace.terminalFontName -string "Source Code Pro for Powerline"

# Default: not documented.
defaults write com.superlogical.rex Workspace.terminalFontPointSize -float 14

# Default: not documented. Block, bar, or underline.
defaults write com.superlogical.rex Workspace.terminalCursorStyle -string underline

# Default: "" (login shell).
defaults write com.superlogical.rex Workspace.terminalStartupCommand -string /opt/homebrew/bin/fish
