---
name: dot:claude-settings
description: Check Claude settings for live drift, bad merges, and unapplied changes.
disable-model-invocation: true
---

# dot:claude-settings

Audit `agents/claude/settings.jsonc` (the repo file) against `~/.claude/settings.json` (the live file), which `dot merge` merges it into (`_merge_claude_settings` in `dot`). Three questions:

1. **Drift:** is the live file holding settings that belong in the repo file?
2. **Merge safety:** would merging the repo file delete or overwrite something it shouldn't?
3. **Applied:** has the repo file been merged yet, or does `dot merge claude` need running?

## Ground rules

- Read-only until the user says otherwise. Applying means `dot merge claude`, which rewrites their live file, so the user runs it.
- The repo is shared across machines. Never move secrets, tokens, or machine paths into it.
- The repo file holds only settings we chose to set, each with a `// Default: ...` comment. A key equal to its default is deliberate; leave it.

## Merge model

- **Live file:** Claude Code writes to it too (`/config`, `/model`, `/plugin`), and other tools install `hooks` there.
- **Merge:** `sqlite3`'s `json()` parses both files as JSONC and `json_patch` (RFC 7396) merges them, repo winning. Objects merge key by key. Arrays and scalars replace wholesale. A `null` in the repo deletes the live key, but removing a key from the repo leaves it live.
- **Why `hooks` never goes in the repo file:** the merge would replace the live array and wipe hooks installed by other tools. A bats test enforces this.

## Known limits

`compare.js` reads sqlite's output with `JSON.parse`, so a change that doesn't survive that parse is invisible even though the merge rewrites it: integers beyond 2^53 (such as 20-digit IDs), `1` vs `1.0`, and `0` vs `-0`. Settings rarely hold such values. If one matters, compare the `json_patch` text in `sqlite3` directly. Duplicate keys in a file also collapse to the last one.

## Steps

1. Run the comparison. It runs the same `json_patch` as `dot merge claude`, without writing anything, and names the repo file it read (check it's the checkout `dot` merges from). It prints three sections:
   - Unapplied: every change the merge would make, as live → merged.
   - Live drift: live keys the repo file lacks.
   - Merge risks: the Unapplied lines that lose live data.

   ```bash
   bun .agents/skills/claude-settings/scripts/compare.js
   ```

2. **Drift.** For each live key the repo file lacks, including entries nested under keys we set (a plugin the repo dropped stays enabled, since the merge never deletes), show a table of key, live value, default, and machine-specific. Add only the ones the user wants. Flag these as likely machine-specific and recommend leaving them out (`compare.js` already hides `hooks` and `apiKeyHelper`):
   - hooks and status lines installed by other tools;
   - auth and endpoints: `apiKeyHelper`, `awsAuthRefresh`, `otelHeadersHelper`, and `env` entries such as `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, proxy and `CLAUDE_CODE_USE_*` variables;
   - model pins tied to an account or gateway: `model`, `ANTHROPIC_DEFAULT_*_MODEL`, `modelSettings`;
   - local paths, and anything holding a secret or token.

   When unsure, ask. Comment each key you add `// Default: <value>.`, or `// Default: unset.`

3. **Merge safety.** Every Merge risks line is live data the merge would lose: an array that drops live entries, a `null` that deletes a live key, or a type change that replaces an object or array. For each, ask whether the user wants the loss. Usually the fix is to add the live entries to the repo array, or drop the `null`. A risk under `hooks` is always a bug: remove the key (see Merge model).

4. **Applied.** Each Unapplied line is a change `dot merge claude` hasn't made yet. If there are any, or if you edited the repo file, run `bats tests/`, then tell the user to run `dot merge claude` and rerun step 1. The audit is done when Unapplied and Merge risks are empty and the user has decided every drift line.

5. **Docs check (optional, after a Claude Code upgrade).** For each repo key, read its **Default** line in https://code.claude.com/docs/en/settings-reference. Claude Code ships no defaults file.
   - Fix a `// Default: ...` comment that doesn't match (`unset` for anything the docs call unset). Check nested keys the docs default separately, such as `autoUpdate` under `extraKnownMarketplaces`.
   - If a key is deprecated, removed or renamed, ask before switching to the replacement the docs name. Removing a key from the repo doesn't remove it from the live file, so tell the user to delete it there too.

   The page is about 450k characters and WebFetch returns 100k per call. Pass `offset` in 100000 steps and ask for every key you need in one prompt per chunk, instead of one fetch per key.

## Report

End with this, skipping empty sections:

```
Drift:       <n> live keys not in the repo (table above); recommend adding <list>
Merge risks: <n> (what each would lose)
Unapplied:   <n> changes; run `dot merge claude`, then rerun the comparison
Docs check:  <fixed comments, deprecated keys, or "not run">
```
