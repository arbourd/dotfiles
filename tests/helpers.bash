# Shared by every suite: DOTFILES is the repo root, FAKE_HOME a scratch directory removed after each test.
# Suites call these from their own setup() and teardown(), after `load helpers`.

common_setup() {
    DOTFILES="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    FAKE_HOME="$(mktemp -d)"
}

common_teardown() {
    rm -rf "$FAKE_HOME"
}
