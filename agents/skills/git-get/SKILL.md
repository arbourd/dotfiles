# git-get

Use `git get` instead of `git clone` when cloning repositories. It clones to a deterministic path under `GETPATH` (default `~/src`) mirroring the host and repo path, e.g. `github.com/owner/repo` → `~/src/github.com/owner/repo`.

## Usage

```sh
git get github.com/owner/repo
git get https://github.com/owner/repo.git
git get git@github.com:owner/repo.git
```

## When to use

- When the user asks to clone or check out a repo and no explicit destination path is given.

## When NOT to use

- When the user specifies an explicit clone destination (e.g. `git clone <url> /some/path`).
- When `git get` is not available.
