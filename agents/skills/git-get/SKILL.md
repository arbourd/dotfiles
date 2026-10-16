---
name: git-get
description: Clone git repositories with `git get` instead of `git clone`, so they land at a predictable path under GETPATH (default ~/src). Use whenever the user asks to clone, check out, or fetch a repo by URL or `owner/repo` and gives no destination path, even if they say "git clone".
---

# git-get

`git get` clones to `$GETPATH/<host>/<owner>/<repo>` (default `GETPATH=~/src`), so every repo has one predictable location, e.g. `github.com/owner/repo` → `~/src/github.com/owner/repo`. Use it in place of `git clone` so repos don't end up scattered in the current directory.

```sh
git get github.com/owner/repo
git get https://github.com/owner/repo.git
git get git@github.com:owner/repo.git
```

After cloning, work from the resulting path under `GETPATH`.

Fall back to `git clone` when the user names an explicit destination (`git clone <url> /some/path`) or `git get` isn't installed.
