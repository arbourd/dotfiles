---
name: git-get
description: Clone git repositories with `git get` instead of `git clone`, so they land at a predictable path under GETPATH (default ~/src). Use whenever the user asks to clone a repo by URL or `host/owner/repo` and gives no destination path, even if they say "git clone".
---

# git-get

`git get` clones to `$GETPATH/<host>/<owner>/<repo>` (default `GETPATH=~/src`), so every repo has one predictable location, e.g. `github.com/owner/repo` → `~/src/github.com/owner/repo`. Use it in place of `git clone` so repos don't end up scattered in the current directory.

```sh
git get github.com/owner/repo
git get https://github.com/owner/repo.git
git get git@github.com:owner/repo.git
```

The host is required: `owner/repo` alone is read as host `owner` and fails. A bare `host/owner/repo` is cloned over HTTPS unless a git `url.<base>.insteadOf` rule rewrites it (e.g. to SSH); for a private repo, pass the `git@host:owner/repo` form.

stdout is only the resulting path (progress and `-v/--verbose` git output go to stderr). Capture it and check the exit status before using it, since a failed clone prints nothing and `cd ""` succeeds in zsh and sh:

```sh
dir=$(git get -- "<repo>") && cd "$dir"
```

If the repo is already cloned, it prints the existing path without cloning, fetching, or pulling; to update it, run `git pull` there.

It takes one repository per call, and options may come anywhere before `--`. `-h`/`--help` and `--version` print and exit 0 (use `git get -h`; git intercepts `git get --help`). A lone `-v` also prints the version, but with a repository it means `--verbose`. Change the root with `$GETPATH` or `git config --global get.path ~/dev` (the env var wins).

`git get` has no `git clone` options (`--depth`, `-b`, `--recurse-submodules`). Use `git clone` for those, or when the user names a destination. If `git get` isn't installed, clone to the same layout yourself: `git clone <url> <root>/<host>/<owner>/<repo>`, where `<root>` is `$GETPATH`, else `git config get.path`, else `~/src` (expand `~` yourself), and `<repo>` has no `.git` suffix.

On an error such as `<dir> exists but <dir>/.git does not` or `GETPATH is not an absolute path`, report it. Don't delete the directory or change git config to work around it.
