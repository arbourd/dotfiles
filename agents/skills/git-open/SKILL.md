---
name: git-open
description: Open a repository, file, commit, or line in the browser with `git open`, or get its web URL. Use when the user asks to open, view, share, or link to the repo, a file, a commit, or a line (e.g. "link me to line 42 of main.go") on GitHub, GitLab, Bitbucket, or Codeberg (or a self-hosted provider), or wants the web URL for something in the current repo. Prints the URL by default (`-n`); launches a browser only when explicitly asked. Not for reading local files.
---

# git-open

`git open [options] [path|commit]` opens the current repo's web page in the browser, inferred from the remote. Supports GitHub, GitLab, Bitbucket, and Codeberg out of the box.

Add `-n` (`--no-browser`), before or after the path, to print only the URL to stdout instead of launching a browser. Always use `-n` when running it yourself. Omit it only when the user explicitly asked to open the page, then ask first.

```sh
git open -n                  # repository root
git open -n main.go          # file or folder
git open -n 7605d91          # commit (lowercase hex SHA, 7-64 chars)
git open -n main.go:42       # line
git open -n main.go:42-50    # line range
git -C ~/src/my-repo open -n # a repo other than the current directory
git open -n -- -odd-name     # `--` makes later args paths, even if they start with `-`

git open -n main.go:42
# https://github.com/owner/repo/tree/feature-x/main.go#L42
```

Use `git open -h` for usage (git intercepts `git open --help`) and `-v`/`--version` for the version. Unknown options and extra arguments exit 1 with `error: ...` on stderr.

## Behavior to know

- URLs use the current branch (the full SHA when HEAD is detached), so they aren't permalinks and 404 if the branch isn't pushed. For a stable link, pass a commit SHA.
- A missing path, a path outside the repo, a path under a file, or `.` yields the current branch's tree URL (on GitHub `.../tree/<branch>`; other providers use a different prefix), not the repo root URL. Check the printed URL if the target matters.
- `:line` is dropped for directories, and ignored if a file literally named `main.go:42` exists.
- Only a lowercase hex SHA is a commit, unless a file with that name exists. `HEAD`, branches, tags, and uppercase SHAs aren't supported and silently give the branch URL.
- Local remotes aren't supported (`local remotes are not supported`), and an unknown host errors with `unable to find provider for: "<host>"`.

## Self-hosted providers

Add a provider with git config (local repo config wins over global). `commitprefix` and `pathprefix` are required, or the provider is skipped. `lineformat` is optional: `%l` is a line number, at most two (start, end). More than two, or other verbs like `%v`, disable line anchors with a warning.

```sh
git config --global open.https://git.example.com.commitprefix commit
git config --global open.https://git.example.com.pathprefix tree
git config --global open.https://git.example.com.lineformat "L%l-L%l"
```
