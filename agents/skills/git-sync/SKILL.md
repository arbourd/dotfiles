---
name: git-sync
description: Update all local branches from their remotes with `git sync`. Use whenever the user asks to sync, refresh, update, or pull every local branch in a repo (not just the current one), prune merged branches, or bring local branches up to date with upstream in one step, even if they don't say "git sync". Plain `git sync` never deletes branches; `git sync --prune` also deletes merged branches whose remote branch is gone, so confirm before running it.
---

# git-sync

`git sync` fetches, then walks every local branch in one command, instead of checking out and pulling each one.

```sh
git sync
```

Its only option is `--prune` (below); a bare `--` is accepted and anything else errors with usage. `-h`/`--help` prints usage and `-v`/`--version` prints the version. Use `-h` rather than `git sync --help`, which git intercepts to open the man page.

## What it does

Fetches and prunes the remote whose `<remote>/HEAD` ref exists (usually `origin`), without fetching or pruning tags; stale remote-tracking refs are removed. Without that ref it fails with `could not find a remote`; fix with `git remote set-head origin -a`. Then, per local branch:

- **Behind its upstream**: fast-forwarded, including the checked-out branch. A branch checked out in another worktree (including one stopped mid-rebase or mid-bisect) is fast-forwarded there, unless that worktree has changes to tracked files (untracked files are ignored), a rebase, bisect, merge, cherry-pick or revert in progress, or the merge fails; then it is left alone, with a warning. A branch checked out in several worktrees is always left alone, with a warning. A branch not tracking that remote is compared with the same-named branch on it, even if it tracks another remote.
- **Not an ancestor of its upstream** (unpushed commits, or diverged: ahead and behind): left alone, with a warning. Diverged branches stay stale and need a manual rebase or merge.
- **Upstream deleted on the remote**: kept with a warning unless `--prune` is passed. With `--prune`, force-deleted locally (`git branch -D`, no prompt, recoverable only via reflog) if its tip is an ancestor of `<remote>/<default>`, or its changes are already there (rebase- or squash-merged; needs git 2.40+). Anything unproven is kept, with a warning. If it's the checked-out branch, `git sync` first checks out the default branch. A branch checked out in another worktree is kept, with a warning, and so is the checked-out branch when the default branch is checked out in another worktree.
- **Identical, or no matching remote branch**: untouched.

Output is one line per change, with the commit the branch was at before. It always includes ANSI colour codes, and warnings go to stdout, so strip the codes before matching text:

```
Updated branch main (was 8915328).
Deleted branch feature-123 (was 7c24329).
warning: 'feature-123' was deleted on origin
warning: 'wip' seems to contain unpushed commits
warning: 'old-idea' was deleted on origin, but appears not merged into 'main'
warning: 'main' not updated: /path/to/worktree has local changes or an operation in progress
warning: 'main' is checked out in several worktrees (/path/a, /path/b), not updated
```

Warnings are not failures, so report them to the user rather than forcing anything.

## Pruning

There is no dry run. Ask the user before adding `--prune`: deletion is forced, and `git branch <name> <sha>` with the `was <sha>` from the output restores a branch.

## Failures

Errors print `error: ...` to stderr and exit 1. The first per-branch error stops the run, and later branches (in ASCII order) are not synced, so tell the user the sync was partial and re-check the rest. Known causes:

- Checking out the default branch (when deleting the checked-out branch) can fail on a dirty working tree.
- git older than 2.36 fails listing worktrees (`git worktree list` rejects `-z`), before anything is fetched; it needs a newer git.

For one branch, use `git pull`.
