---
name: tabulate
description: Tabulate findings with stable IDs. Use for a requested findings table, or to consolidate findings from multiple sources.
---

# tabulate

## Steps

1. Collect. Read every source in full. Account for each finding as a candidate row.
2. Merge. Combine rows that share a root cause only when one fix resolves them all. Keep repeated instances separate when each needs its own fix. Retain every location and source in the merged row.
3. Filter. Put false positives and findings outside the requested scope in Dropped. Unless the user limits the scope to the change, retain pre-existing findings. If evidence establishes origin, mark them as pre-existing in Origin or the Finding text.
4. Rank. Sort retained rows by severity for reviews, or by priority for other work. Break ties by confidence in the supporting evidence. Repeated claims alone add no confidence.
5. Number. On the first pass, assign `F1`, `F2`, … in ranked order. Preserve assigned IDs throughout the conversation. Give each new finding the next unused ID, regardless of its rank. If a later merge combines rows with assigned IDs, keep the earliest assigned ID. Record each other ID in Dropped with the reason `merged into F<m>`.
6. Render. Account for every collected finding in a retained row or Dropped. Count each finding combined into another row as accounted for by that row. If no findings remain, state that result.

## Table

Keep the table scannable. Keep ID first and Finding near the front.
For reviews, start from ID, Severity, Finding, Location, and Recommendation. Put added columns between Location and Recommendation.
Choose optional columns that help the user compare findings and decide what to do.
If an optional column has the same value in every row, state that value once above the table.
If an optional column has values in only a few rows, put those values in detail sections.
Combine overlapping columns. Populate cells from supported information and leave unsupported cells blank.

Candidate columns:

- Severity: critical, high, medium, low, info. For work that is not a review, rename the column Priority and use high, medium, low.
- Finding: a short phrase naming the issue and its impact.
- Location: `path:line` or a component name.
- Recommendation: a lowercase verb, a colon, and a short, concrete action or reason.
  Examples: `fix: preserve IDs when sorting`, `drop: unused retry flag`, `skip: intentional per the spec`.
- Axis: the review dimension, such as correctness, security, or performance.
- Origin: introduced by the change or pre-existing.
- Source: the person, agent, or document that raised the finding.
- Status: the current state, such as open or resolved.

If the task or user requires other columns, add them.

- Keep each row on one line. Put code in backticks and escape `|` in cells.
- Put the finding count above the table. If Severity or Priority is present, include counts per level.
  Example: `12 findings: 1 critical, 3 high, 8 medium.`

Put long details, such as the failure scenario, cause, and evidence, in a `### F<n>` section under the table.
Add a section only for findings with details that the table omits.

## Dropped

Put rejected or merged findings in a separate table. Keep Finding and Reason. If existing IDs are available, include them.
Choose other columns, such as Source or Location, using the selection and readability rules above.
If this section is empty, omit it.

## Recommendations

Put a short action summary at the bottom, after details and Dropped.
Lead with the highest severity or priority. Group related recommendations and cite every associated finding ID.
If no retained findings have recommendations, omit this section.
