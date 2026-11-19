---
name: trash
description: Delete files and directories with `trash` instead of `rm` / `rm -rf`, moving them to the macOS Trash so they stay recoverable. Use whenever about to remove, delete, or clean up a path on macOS.
---

# trash

`trash <paths>` moves each path to the macOS Trash. Files and directories both work, with no flags: `trash -r` and `trash -f` don't exist.

```sh
trash old.log build/ notes.txt
```

Every argument is a path, except `-h`/`--help` and `-v`/`--version`. Quote paths with spaces; prefix a name starting with `-` with `./`.

Exit 0 means every path was trashed. A failed path prints to stderr and exits 1.
