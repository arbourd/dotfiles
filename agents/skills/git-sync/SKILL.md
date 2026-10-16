---
name: git-sync
description: Update all local branches from their remotes with `git sync`. Use whenever the user asks to sync, refresh, or update every local branch in a repo (not just the current one), or wants local branches brought up to date with upstream in one step.
---

# git-sync

`git sync` updates all local branches from their remotes in one command, instead of checking out and pulling each branch. It's extracted from the `sync` command in github/hub.

```sh
git sync
```

It prints one line per updated branch with the commit it was at before:

```
Updated branch main (was 8915328).
Updated branch feature-123 (was 7c24329).
```

For one branch, use `git pull`.
