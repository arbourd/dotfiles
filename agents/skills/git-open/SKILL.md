---
name: git-open
description: Open a repository, file, commit, or line in the browser with `git open`. Use whenever the user asks to open, view, or link to the repo, a file, a commit, or a line on GitHub, GitLab, Bitbucket, or Codeberg, or wants the web URL for something in the current repo.
---

# git-open

`git open` opens the current repo's web page in the browser, inferred from the remote. Supports GitHub, GitLab, Bitbucket, and Codeberg out of the box.

```sh
git open                  # repository root
git open main.go          # file or folder
git open 7605d91          # commit
git open main.go:42       # line
git open main.go:42-50    # line range
git -C ~/src/my-repo open # a repo other than the current directory
```

Self-hosted providers need a one-time config; `%l` is the line number (at most two):

```sh
git config --global open.https://git.example.com.commitprefix commit
git config --global open.https://git.example.com.pathprefix tree
git config --global open.https://git.example.com.lineformat "L%l-L%l"
```
