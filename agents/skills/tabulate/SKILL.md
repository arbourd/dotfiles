---
name: tabulate
description: Tabulate findings with stable IDs. Use for a requested findings table, or to consolidate findings from multiple sources.
---

# tabulate

## Steps

1. Collect. Read every source in full. Account for each finding as a candidate row.
2. Merge. Combine rows only when they share a root cause and location. Retain every source that raised the finding.
3. Rank. Place false positives and findings outside the requested scope in Dropped. Keep pre-existing findings in the table unless the user limited the scope to the change. Sort retained rows by severity for reviews, or by priority for other work. Break ties by confidence in the supporting evidence. Repeated claims alone add no confidence.
4. Number. Assign `F1`, `F2`, … in ranked order on the first pass. Preserve assigned IDs throughout the conversation, and never reuse one. Give each new finding the next unused ID, even if it ranks above existing rows. If a later merge combines rows that already have IDs, keep the earliest ID. Record each other ID in Dropped with the reason `merged into F<m>`.
5. Render. Account for every collected finding in a retained row, a merged row, or Dropped. If none remain, state that no findings remain.

## Table

Keep ID and Finding. Choose additional columns that help the user compare findings and decide what to do:

- Severity: critical, high, medium, low, info. For work that is not a review, rename the column Priority and use high, medium, low.
- Finding: a short phrase naming the issue and its impact.
- Location: `path:line` or a component name.
- Axis: the review dimension, such as correctness, security, or performance.
- Origin: whether the change introduced the finding or it was pre-existing. Populate it only when the evidence establishes origin.
- Failure scenario: the trigger and resulting failure.
- Cause: the underlying reason for the issue.
- Evidence: the observation that supports the finding.
- Source: the person, agent, or document that raised the finding.
  Include Source when attribution helps distinguish findings or explain agreement between sources.
  If all findings share one source, name it once above the table when the context does not already identify it.
- Status: the current state, such as open or resolved.
- Recommendation: a short, concrete action, such as `Preserve IDs when sorting`.

Add other columns when the task or user requires them. Include columns only when they contain supported information and help comparison.
Leave unsupported cells blank. Combine overlapping columns and omit columns that are empty across all rows.

- Put ID first and Finding near the front. Put Severity or Priority early when present.
- Put context columns beside Finding and Recommendation near the end. Use the candidate list as a guide. Adapt the order to the task.
- Keep each cell on one line. Put code in backticks and escape `|`.
- Keep all retained findings as rows.
- Put the finding count above the table. If Severity or Priority is present, include counts per level.
  Example: `12 findings: 1 critical, 3 high, 8 medium.`

Keep the table readable at a glance.
If extra columns make it hard to scan, move their contents into detail sections.
If a finding needs supporting details, add a `### F<n>` section under the table.
Put long details and supporting information omitted from the table there.

## Dropped

Put rejected or merged findings in a separate table. Keep Finding and Reason, and include existing IDs when available.
Choose other columns, such as Source or Location, using the selection and readability rules above.
If this section is empty, omit it.
