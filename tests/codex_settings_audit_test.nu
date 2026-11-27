# Run these tests with tests/run.

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

# Runs compare.js with repo and live TOML files in a scratch home.
def _compare [ctx: record, repo: string, live: string]: nothing -> record {
    let skill = $"($ctx.home)/repo/.agents/skills/codex-settings-audit/scripts"
    mkdir $skill $"($ctx.home)/repo/agents/codex" $"($ctx.home)/.codex"
    cp $"($DOTFILES)/.agents/skills/codex-settings-audit/scripts/compare.js" $skill
    $"($repo)\n" | save -f $"($ctx.home)/repo/agents/codex/config.toml"
    $"($live)\n" | save -f $"($ctx.home)/.codex/config.toml"
    let r = with-env {HOME: $ctx.home} { run-external bun $"($skill)/compare.js" o+e>| complete }
    {status: $r.exit_code, output: ($r.stdout | str trim)}
}

@test
def "codex-settings-audit compare.js reports unapplied values and live drift, and skips local keys" [] {
    let c = $in
    let r = _compare $c "[tui]\ntheme = \"dark\"\nalt = [1]" "model = \"m\"\n[tui]\ntheme = \"light\"\nalt = [1]\nnew = true\n[projects.x]\ntrust_level = \"trusted\""
    assert equal $r.status 0
    assert equal $r.output "# Unapplied: in config.toml, not yet in ~/.codex/config.toml\ntui.theme ours=\"dark\" live=\"light\"\n\n# Live drift: set in ~/.codex/config.toml, not in config.toml\ntui.new live=true"
}

@test
def "codex-settings-audit compare.js redacts secrets and keeps other values" [] {
    let c = $in
    let r = _compare $c "[credentials]\nvalue = \"FAKE_REPO\"" "model_auto_compact_token_limit = 100000\npreferred_auth_method = \"chatgpt\"\nAPIKey = \"FAKE_ACRONYM\"\napikey = \"FAKE_NOSEP\"\ntokens = [\"FAKE_PLURAL\"]\nbearer = \"FAKE_BEARER2\"\nbasicauth = \"FAKE_BASICAUTH\"\n[credentials]\nvalue = \"FAKE_LIVE\"\n[shell_environment_policy.set]\nGITHUB_PAT = \"FAKE_PAT\"\n[mcp_servers.x]\nurl = \"https://e.x\"\nbearer_token = \"FAKE_BEARER\"\nbearer_token_env_var = \"X_TOKEN\"\n[mcp_servers.x.env.NESTED]\nvalue = \"FAKE_ENV\"\n[mcp_servers.x.http_headers]\nX-Custom = \"FAKE_HEADER\""
    assert equal $r.status 0
    assert not ($r.output | str contains 'FAKE_')
    assert str contains $r.output 'credentials.value ours="<redacted>" live="<redacted>"'
    assert str contains $r.output 'shell_environment_policy.set.GITHUB_PAT live="<redacted>"'
    assert str contains $r.output 'mcp_servers.x.bearer_token live="<redacted>"'
    assert str contains $r.output 'mcp_servers.x.env.NESTED.value live="<redacted>"'
    assert str contains $r.output 'mcp_servers.x.http_headers.X-Custom live="<redacted>"'
    assert str contains $r.output 'model_auto_compact_token_limit live=100000'
    assert str contains $r.output 'preferred_auth_method live="chatgpt"'
    assert str contains $r.output 'APIKey live="<redacted>"'
    assert str contains $r.output 'mcp_servers.x.bearer_token_env_var live="X_TOKEN"'
    assert str contains $r.output 'mcp_servers.x.url live="https://e.x"'
}

@test
def "codex-settings-audit compare.js fails with one line on malformed TOML" [] {
    let c = $in
    let r = _compare $c '' 'a = ['
    assert equal $r.status 1
    assert str contains $r.output 'compare.js: '
    assert not ($r.output | str contains '    at ')
}
