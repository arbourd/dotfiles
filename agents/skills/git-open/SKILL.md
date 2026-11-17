---
name: git-open
description: Get the web URL for, or open in the browser, the current Git repo, a file, folder, commit, or line with `git open`. Use when the user asks for a link to code or to open, view, or share the repo, a file, a line, or a commit, e.g. "link me to line 42 of main.go" or "give me a permalink". Not for PRs, issues, CI, blame, or reading local files.
---

# git-open

`git open [options] [path|commit]` prints or opens the web page for the current repo, built from the remote URL (the default remote, or `-R <name>`).

## Rules

1. **Match the flag to the request.** If the user asks to open something in their browser ("open main.go in the browser"), run it without `-n`: that is what launches the browser, and it prints `Opening <url> in your browser.` For anything else, such as a link, a URL, or sharing, pass `-n` (`--no-browser`, before or after the path) and give them the printed URL. When it's unclear which they want, print with `-n` and offer to open it.
2. **Give the user the printed URL as is.** Path prefixes and line anchors differ by provider (GitLab `/-/tree/main/a.go#L3-5`, Bitbucket `/src/main/a.go#lines-3:5`), so a hand-built or edited URL is likely wrong.
3. **Run it inside the repo,** or run `git -C <dir> open` with the same arguments.

## Recipes

The flag follows the request:

```sh
git open -n main.go:42   # "link me to line 42 of main.go": print the URL
# https://github.com/owner/repo/tree/feature-x/main.go#L42

git open main.go         # "open main.go in the browser": launch it
```

With no argument it targets the repo root, and a path may be a file or a folder. Other forms, shown without a flag (add `-n` to print the URL instead of opening the browser):

```sh
git open main.go:42         # line; `main.go:42-50` for a range
git open 7605d91            # commit
git open -r main README.md  # link to main, for an unpushed branch; any branch or tag works
git open -R fork main.go    # build the URL from remote `fork`
git open -- -odd-name       # `--` makes later args paths, even with a leading `-`
```

**Stable link (permalink):** a plain path uses the current branch, so the link changes as the branch moves. Pin it to a commit with `-r`:

```sh
git open -n -r "$(git rev-parse HEAD)" main.go:42
# https://github.com/owner/repo/tree/<full-sha>/main.go#L42
```

## Gotchas

- **Ref:** the current branch, or the full SHA when HEAD is detached. `-r` replaces it and is used literally, so `origin/main` 404s; use `main`. `-r` can't be combined with a commit argument.
- **Not validated:** URLs are built from local state and nothing is checked against the remote. They 404 if the branch or commit isn't pushed, or the path doesn't exist at that ref, and line numbers refer to the pushed file, so uncommitted edits can shift them.
- **Paths:** relative to the current directory, or absolute. A path missing locally is kept, since it may exist at that ref. A path outside the repo, or `.` at the repo root, gives the tree URL of the ref (on GitHub `.../tree/<branch>`), not the repo root URL.
- **`:line`:** ignored for directories, and ignored when a file literally named `main.go:42` exists.
- **Commits:** only a lowercase hex SHA is a commit (it opens the commit page, not the file at that commit), unless a file with that name exists. `HEAD`, branch names, tags, and uppercase SHAs are treated as paths and give a URL that 404s (for example `.../tree/<branch>/HEAD`). Use `-r <ref>` for a branch or tag, and `git rev-parse` to turn `HEAD` into a SHA.
- **Errors:** they print `error: <message>` and exit 1. `exit status 128` usually means no remote or no commits.

## Self-hosted providers

An unknown host errors with `unable to find provider`. Add one with git config; `commitprefix` and `pathprefix` are required, `lineformat` is optional (`%l` is a line number). Suggest the commands to the user rather than changing their config:

```sh
git config --global open.https://git.example.com.commitprefix commit
git config --global open.https://git.example.com.pathprefix tree
git config --global open.https://git.example.com.lineformat "L%l-L%l"
```

## More

`git open -h` prints usage; `git open --help` opens the man page.
