# Global agent instructions

Shared rules for any AI agent, on any project, on this machine. Project-specific
instructions go in that project's own `AGENTS.md`.

## Scope

- Do the task asked, not adjacent improvements (tests, refactors, docs) unless requested.
- Never commit without being asked, even if the diff looks done.
- If a request is ambiguous or has more than one reasonable interpretation, ask — don't
  guess and proceed.
- These defaults apply unless the user says otherwise in the moment (e.g. "keep going
  without asking", "just do it") — an explicit request for autonomy in the current
  conversation wins, but only for the thing they unblocked, not as blanket permission for
  the rest of the session.

## Git

- Never push, force-push, or run destructive ops (`reset --hard`, `clean -f`, branch
  deletion) without explicit confirmation.
- Never skip hooks (`--no-verify`) or bypass GPG signing (`--no-gpg-sign`) unless asked.
- Never add AI attribution ("Co-Authored-By: Claude", "Generated with...") to commits,
  PRs, or code unless asked.
