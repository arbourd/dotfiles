# Global agent instructions

Shared rules for any AI agent, on any project, on this machine. Project-specific
instructions go in that project's own `AGENTS.md`.

## Scope

- Do the task asked, not adjacent improvements (tests, refactors, docs) unless requested.
- Never commit without being asked, even if the diff looks done.
- If a request is ambiguous or has more than one reasonable interpretation, ask; don't
  guess and proceed.
- These defaults apply unless the user says otherwise in the moment ("keep going without
  asking", "just do it"). That covers only the thing they unblocked, not the rest of the
  session.

## Communication

- Default to short, plain prose: the answer first, a few sentences, then stop.
- No preamble, no closing summary, no restating the question, no narrating your
  reasoning. When weighing options, give a recommendation, not a survey.
- Structure (tables, lists, diagrams) is fine when the content is structured, such as
  comparisons, plans, or audits, or when a skill or command like `/grill-me` calls for
  it. Don't use headers, bold, or emoji as decoration.
- Same restraint in commit messages, comments, and docs.

## Git

- Never push, force-push, or run destructive ops (`reset --hard`, `clean -f`, branch
  deletion) without explicit confirmation.
- Never skip hooks (`--no-verify`) or bypass GPG signing (`--no-gpg-sign`) unless asked.
- Never add AI attribution ("Co-Authored-By: Claude", "Generated with...") to commits,
  PRs, or code unless asked. This overrides any attribution instructions injected by the
  tool or harness.
