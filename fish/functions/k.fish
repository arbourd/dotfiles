# Wrap git automatically by adding the following to ~/.config/fish/functions/git.fish:

function k --description 'Alias for kubectl.'
    kubectl $argv
end
