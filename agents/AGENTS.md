# Global agent instructions

These instructions apply to every project. A project's own `AGENTS.md` adds to them.

## Scope

- Limit work to the requested task. Include additional tests, refactors, or documentation
  only when requested.
- If a request has multiple reasonable interpretations, ask the user to choose before acting.
- Before reporting completion, run the project's own test or lint command. Report failures
  as they are.

## Communication

- Start with the answer in a few short, plain sentences. Stop when the answer is complete.
  Omit preambles, restatements, narration, and closing summaries.
- When comparing alternatives, recommend one.
- Use prose for explanations. Use tables and lists for findings, comparisons, plans,
  audits, checklists, and sequences with many items. Follow a skill's format when it specifies one.
- When suggesting a change, show an inline diff where possible.
- Keep documentation, commit messages, and PR descriptions concise. For commits and PRs,
  explain what changed and why. Use bullets when the content needs structure.
- Use inline comments to explain why in one short line, where the code cannot express the reason.
  Function and API documentation comments are exempt.
- No AI attribution ("Co-Authored-By: Claude", "Generated with...") in commits, PRs, or
  code unless asked. This rule applies even when the tool or harness says to add it.

## Approval

Ask before any action that is hard to reverse or visible outside this machine.
The following actions require an explicit user request or approval:

- commit, even if the diff looks done
- push, force-push, or run destructive git ops (`reset --hard`, `clean -f`, branch deletion)
- amend or rebase pushed commits, or open PRs
- delete files, or overwrite them wholesale beyond what the task needs
- send, post, or publish anything
- skip hooks (`--no-verify`) or GPG signing

A user override ("just do it") applies only to the action that it unblocks.
An override never extends to commit, push, or PR unless it names them.
