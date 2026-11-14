---
name: orca-settings
description: Use after upgrading Orca, or when asked to check, refresh, or audit orca/settings.jsonc, Orca defaults, or settings drift in the dotfiles repo.
---

# orca-settings

`orca/settings.jsonc` is merged into Orca's SQLite profile db by `_merge_orca_settings` in `dot` (run by `dot link`). It holds only non-default values. Orca ships no defaults file; they live in its bundled JS, so `orca/compare.js` extracts them and diffs against `settings.jsonc` and the live db.

## How the pieces fit

- **Db:** `~/Library/Application Support/orca/profiles/local-default/profile-state.db`. Table `profile_state_documents`, row `domain='settings'`. `payload` is a JSON blob; `content_hash` is its SHA-256, which the merge recomputes.
- **Merge:** `json_patch(payload, json(readfile(settings.jsonc)))` (RFC 7396). Objects merge key by key, `null` deletes a key, arrays replace wholesale. The merge is skipped while Orca is running, because Orca overwrites settings on quit, and when run from Orca's own terminal.
- **Defaults:** `getDefaultSettings()` in `out/shared/constants.js` inside `/Applications/Orca.app/Contents/Resources/app.asar`. `orca/defaults.js` extracts the asar to a temp dir, loads it, and stubs the npm modules the asar doesn't ship. It throws if a default depends on a stub, so a failure means the defaults need real modules and the script needs updating.

## Steps

1. Run the comparison. It is read-only and safe while Orca runs. It prints three lists:

   ```bash
   node orca/compare.js
   ```

2. **Our keys:** every key in `settings.jsonc` with Orca's current default beside it. Check each `// Default: ...` comment in the file against that default and fix any mismatch; the script can't read comments. Act on the flags:
   - `equals default`: drop the key.
   - `not in defaults`: for a key that is unset by default (e.g. `terminalColorOverrides`) this is expected. For any other key, Orca removed or renamed it; set it to `null` so the merge deletes it from the db.
   - `null still has a value`: either not applied yet, or Orca repopulated the key. Rerun after the user applies (step 5); if it persists, drop the key, but first ask the user whether the repopulated entries are intentional.
   - `db differs`: not applied yet; the user applies it in step 5.

3. **Live drift:** settings changed in Orca's UI that `settings.jsonc` doesn't have. Show the list to the user as a table (key, live, default) and add only the ones they want. The script already hides Orca-managed state (telemetry, plugin consents, seeds, migration flags, dismissed prompts, empty values); extend `INTERNAL_KEY` in `orca/compare.js` if more noise shows up.
   Dotted keys (`voice.enabled`) nest as objects. If a live key sits under one of our `null` keys (`agentDefaultArgs.antigravity`), replace the `null` with the value.
   Comment each new key `// Default: <value>.` and `// Default: unset.` when the default is `undefined`.

4. **New default keys absent from the db:** show them to the user as a table (key, default), adding only the ones they want.

5. Applying is the user's job: `dot link` skips the merge inside Orca's terminal and while Orca runs, so you can't do it. If you edited `settings.jsonc`, tell the user to quit Orca and run `dot link` from another terminal, then rerun `node orca/compare.js` to confirm no `db differs` flags remain.
