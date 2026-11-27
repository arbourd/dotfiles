---
name: codex-settings-audit
description: Check Codex settings for live drift, stale defaults, and unapplied changes.
disable-model-invocation: true
---

# codex-settings-audit

Audit `agents/codex/config.toml` against the live file `dot merge codex` merges it into (`_merge_codex_config` in `dot`): `~/.codex/config.toml`. Three questions:

1. **Drift:** is the live file holding settings that belong in the repo file?
2. **Defaults:** does each repo key still differ from its default, with a correct `# Default: ...` comment?
3. **Applied:** has the repo file been merged yet, or does `dot merge codex` need running?

## Ground rules

- Read-only until the user says otherwise. Applying means `dot merge codex`, which rewrites their live file, so the user runs it.
- The repo is shared across machines: keep secrets, tokens, and machine paths out of it.
- The repo file holds only non-default values. Put `# Default: <value>` directly above each key. For an unset default, write `unset`. Exceptions: `approval_policy`, `approvals_reviewer`, and `sandbox_mode` stay together for auto mode, and `tui.status_line_use_colors` is kept by choice.
- Marketplace and plugin tables need no default comment. Keep a marketplace's `source`, including `.git`, directly before `ref` for Renovate.

## Merge model

- **Live file:** Codex writes to it too (project trust, notices, model choices). `compare.js` hides those keys from Live drift through `LOCAL_KEYS`. Extend that set only for keys that never belong in the repo.
- **Merge:** a `yq` deep merge, repo winning. Tables merge key by key. Arrays and scalars replace wholesale. The merge strips all comments from the live file. There is no null-delete, so removing a key from the repo leaves it live, including entries inside marketplace and plugin tables.

## Steps

1. Run the comparison. It parses both files with `yq` as the merge does, without writing anything. It prints two sections:
   - Unapplied: repo values the live file does not match yet, as ours and live.
   - Live drift: live keys the repo file lacks, including nested entries.

   ```bash
   bun .agents/skills/codex-settings-audit/scripts/compare.js
   ```

2. **Drift.** For each Live drift line, show a table of key, live value, default, and machine-specific. Redact secrets. Add only the ones the user wants, with a `# Default: ...` comment. Flag auth, local paths, and anything holding a secret or token as machine-specific and recommend leaving it out. When unsure, ask.

3. **Defaults.** Run `codex --version`. For each repo key and each drift key, read its default in these docs:
   - https://learn.chatgpt.com/docs/config-file/config-reference.md
   - https://learn.chatgpt.com/docs/config-file/config-sample.md

   Compare each default with the source or settings schema in https://github.com/openai/codex at the installed release tag. The docs lag releases. If the docs disagree with the source or say nothing, use the source.
   - Fix a `# Default: ...` comment that does not match.
   - Drop a key whose value equals its default, except the deliberate ones in Ground rules.
   - If a key is deprecated, removed, or renamed, ask before switching to the replacement the docs name. Tell the user to delete the old key from the live file too.
   - If a default stays unresolved, keep the key and say what evidence is missing.

4. **Applied.** Each Unapplied line is a change `dot merge codex` has not made yet. If there are any, or if you edited the repo file, run `tests/run`. Then give the user these steps:
   1. Delete the live keys marked for removal.
   2. Run `dot merge codex`.
   3. Rerun step 1.

   When Unapplied is empty and the user decided every drift line, the audit is done.

## Report

End with this, skipping empty sections:

```
Drift:     <n> live keys not in the repo (table above); recommend adding <list>
Defaults:  <fixed comments, dropped keys, deprecated keys, unresolved defaults, with source links>
Unapplied: <n> changes; run `dot merge codex`, then rerun the comparison
Removals:  <live keys the user must delete by hand>
```
