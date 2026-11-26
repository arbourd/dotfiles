
use std/assert
use std/testing *

const DOTFILES = (path self | path dirname | path dirname)

@before-each
def setup [] {
    {home: (mktemp -d)}
}

@after-each
def teardown [] {
    rm -rf $in.home
}

@test
def "renovate managers for internal/install/pins.go match the vim-plug version and Homebrew sha" [] {
    # Nushell regexes lack named groups, so use JavaScript as Renovate does.
    let r = ^bun -e r#'
        const fs = require("fs");
        const [renovate, file] = process.argv.slice(1);
        const text = fs.readFileSync(file, "utf8");
        const managers = JSON.parse(fs.readFileSync(renovate, "utf8")).customManagers
            .filter((m) => m.managerFilePatterns.includes("internal/install/pins.go"));
        const found = managers.flatMap((m) => m.matchStrings)
            .flatMap((s) => [...text.matchAll(new RegExp(s, "g"))].map((x) => x.groups));
        console.log(JSON.stringify(found));
    '# $"($DOTFILES)/.github/renovate.json" $"($DOTFILES)/internal/install/pins.go" o+e>| complete
    assert equal $r.exit_code 0
    let found = $r.stdout | from json
    let vim = $found | where depName? == "junegunn/vim-plug"
    assert equal ($vim | length) 1
    assert equal ($vim | first | get currentValue) "0.15.0"
    assert equal ($vim | first | get datasource) "github-tags"
    let brew = $found | where {|g| ($g.currentDigest? | default '') =~ '^[0-9a-f]{40}$' }
    assert equal ($brew | length) 1
    assert ($"($DOTFILES)/internal/install/pins.go" | open | str contains ($brew | first | get currentDigest))
}
