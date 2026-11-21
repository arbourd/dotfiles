# Tests for tests/run itself, run with:
#   tests/run
#
# Each test writes a fixture suite into its scratch home and runs tests/run against it with --path.

use std/assert
use std/testing *

const RUNNER = (path self | path dirname | path join run)

@before-each
def setup [] {
    {home: (mktemp -d)}
}

@after-each
def teardown [] {
    rm -rf $in.home
}

# suite writes a fixture suite whose teardown touches <home>/torn-down/<test>.
def suite [ctx: record, tests: string] {
    $"use std/assert
use std/testing *

@before-each
def setup [] { {marker: '($ctx.home)/torn-down'} }

@after-each
def teardown [] { mkdir $in.marker }

($tests)
" | save $"($ctx.home)/fixture_test.nu"
}

# runner runs tests/run against the fixture suite.
def runner [ctx: record, ...args: string]: nothing -> record {
    let r = ^nu -n $RUNNER --path $ctx.home ...$args | complete
    {status: $r.exit_code, output: ($r.stdout + $r.stderr | ansi strip)}
}

@test
def "runner fails and names only the failing test, and still tears it down" [] {
    let c = $in
    suite $c "@test\ndef \"it fails\" [] { assert equal 1 2 }\n\n@test\ndef \"it passes\" [] { assert equal 1 1 }"
    let r = runner $c 'fails'
    assert equal $r.status 1
    # only the failing test ran, so the marker proves its teardown ran
    assert ($"($c.home)/torn-down" | path exists)

    let r = runner $c
    assert equal $r.status 1
    assert str contains $r.output "FAIL fixture_test: it fails"
    assert not ($r.output | str contains "FAIL fixture_test: it passes")
    assert str contains $r.output "These are not equal"
    assert str contains $r.output "2 tests, 1 failed"
}

@test
def "runner runs only tests matching the pattern" [] {
    let c = $in
    suite $c "@test\ndef \"it passes\" [] { assert equal 1 1 }\n\n@test\ndef \"it fails\" [] { assert equal 1 2 }"

    let r = runner $c 'passes'
    assert equal $r.status 0
    assert str contains $r.output "1 tests, 0 failed"
}

@test
def "runner fails when no tests are found or the pattern matches none" [] {
    let c = $in
    let r = runner $c
    assert equal $r.status 1
    assert str contains $r.output "no tests found"

    suite $c "@test\ndef \"it passes\" [] { assert equal 1 1 }"
    let r = runner $c 'nomatch'
    assert equal $r.status 1
    assert str contains $r.output "no tests found"
}
