package install

// Pinned versions updated by Renovate. Keep markers above their values and URLs on one line.

// renovate: datasource=github-tags depName=junegunn/vim-plug
const VimPlugVersion = "0.15.0"

// BrewInstallURL is the Homebrew installer pinned to a Homebrew/install commit.
var BrewInstallURL = "https://raw.githubusercontent.com/Homebrew/install/6cb910c93f8194b1661a490278a488482399d380/install.sh"

// VimPlugURL is the pinned vim-plug script.
var VimPlugURL = "https://raw.githubusercontent.com/junegunn/vim-plug/" + VimPlugVersion + "/plug.vim"

// FisherBaseURL is the Fisher repository's raw-content root; the version comes from
// sh/fish_plugins. It is a variable so tests can point it at httptest.
var FisherBaseURL = "https://raw.githubusercontent.com/jorgebucaran/fisher"
