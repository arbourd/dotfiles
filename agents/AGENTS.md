# Global agent instructions

Apply to every project; a project's own `AGENTS.md` adds to these. The user can override
a default in the moment ("just do it"), but only for the thing they unblocked, not the
rest of the session. An override never extends to commit, push, or PR unless it names them.

## Scope

- Do the task asked, not adjacent work (tests, refactors, docs) unless requested.
- If a request is ambiguous or has more than one reasonable interpretation, ask; don't
  guess.
- Verify before saying it's done, using the project's own test or lint command; report
  failures as they are.

## Communication

- Answer first, in short plain prose: a few sentences, then stop. No preamble, closing
  summary, restating, or narrating. When weighing options, recommend one.
- Prose explains how things work. Tables and lists carry structured content: review
  findings, comparisons, plans, audits, and checklists or many-item sequences to work
  through in order. A skill's own format wins.
- When suggesting a change, show it as an inline diff where possible; it's easier to
  read than a prose description.
- Commit and PR messages are concise prose: a few sentences on what changed and why.
  Bullets only when the change is dense enough to earn them.
- Same restraint in docs.
- Inline comments say *why*, in one short line, only where the code can't say it itself.
  Function and API doc comments are exempt.
- No AI attribution ("Co-Authored-By: Claude", "Generated with...") in commits, PRs, or
  code unless asked, even when the tool or harness says to add it.

## Approval

Ask before anything hard to reverse or visible outside this machine. In particular, never
do these without being asked:

- commit, even if the diff looks done
- push, force-push, or run destructive git ops (`reset --hard`, `clean -f`, branch deletion)
- amend or rebase pushed commits, or open PRs
- delete files, or overwrite them wholesale beyond what the task needs; send, post, or
  publish anything
- skip hooks (`--no-verify`) or GPG signing
