---
name: claude-settings
description: Use after upgrading Claude Code, or when asked to check, refresh, or audit agents/claude/settings.jsonc, Claude Code setting defaults, or settings drift in the dotfiles repo.
---

# claude-settings

`agents/claude/settings.jsonc` is merged into `~/.claude/settings.json` by `_merge_claude_settings` in `dot` (run by `dot merge`). It holds only non-default values, each with a `// Default: ...` comment. `scripts/compare.js` diffs it against the live file; checking defaults is done by reading the docs.

## How the pieces fit

- **Live file:** `~/.claude/settings.json`. Claude Code writes to it too (`/config`, `/model`, `/plugin`), and other tools install `hooks` there.
- **Merge:** `sqlite3`'s `json()` parses both files as JSONC, and `json_patch` (RFC 7396) merges them (repo wins). Objects merge key by key, and arrays and scalars replace wholesale. A `null` in the repo deletes the key from the live file, but removing a key from `settings.jsonc` leaves it in the live file. That's why `settings.jsonc` must never get a `hooks` key (a bats test enforces this).
- **Defaults:** Claude Code ships no defaults file. Each key's section in https://code.claude.com/docs/en/settings-reference has a **Default** line, and the settings index marks deprecated keys.

## Steps

1. Run the comparison. It is read-only:

   ```bash
   node .agents/skills/claude-settings/scripts/compare.js
   ```

2. **Unapplied:** keys in `settings.jsonc` that the live file doesn't match yet. The user applies them in step 5.

3. **Live drift:** keys in `~/.claude/settings.json` that `settings.jsonc` doesn't have, including entries nested inside keys we do set (a plugin under `enabledPlugins` that the repo dropped stays enabled, since the merge never deletes). Show them to the user as a table (key, live value, default from the docs, machine-specific?) and add only the ones they want.

   The repo is shared across machines, so much of the drift belongs only to this one. Flag these as likely machine-specific and recommend leaving them out (`scripts/compare.js` already hides the ones in `LOCAL_KEYS`, which should only hold keys that are never shared):
   - hooks and status lines installed by other tools;
   - auth and endpoints: `apiKeyHelper`, `awsAuthRefresh`, `otelHeadersHelper`, and `env` entries such as `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, proxy and provider (`CLAUDE_CODE_USE_*`) variables;
   - model pins tied to an account or gateway: `model`, `ANTHROPIC_DEFAULT_*_MODEL`, `modelSettings`;
   - local paths, and anything holding a secret or token.

   When unsure, ask. Never move secrets, tokens, or machine paths into the repo.

4. **Our keys:** for each key in `settings.jsonc`, read its section in the settings reference and:
   - fix the `// Default: ...` comment if it doesn't match (`unset` for anything the docs call unset);
   - drop the key if its value equals the default;
   - if it's deprecated, removed, or renamed, switch to the replacement the docs name, after asking the user. Removing a key from the repo doesn't remove it from the live file, so tell the user to delete it there too.

   Check nested keys the docs give their own default for (e.g. `autoUpdate` in `extraKnownMarketplaces`) the same way. Comment each new key `// Default: <value>.`.

5. Applying is the user's job, since it rewrites their live settings. If you edited `settings.jsonc`, run `bats tests/dot.bats`, then tell the user to run `dot merge claude` and rerun `scripts/compare.js` to confirm nothing is listed under Unapplied.
