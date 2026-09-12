# Comm-Log Send Reconciliation

## Xeno Data Analyst Internship Assignment

Reconciliation of Finance's `target_base` metric for:

- **Merchant:** 501
- **Period:** October 2026
- **Communication type:** `2`
- **Finance target:** 22

---

## Objective

Reproduce Finance's reported `target_base` of **22** from the raw campaign and communication-log data and explain the difference between the most naive count and the Finance number.

The analysis was performed in SQLite using the provided `campaign` and `communication_log` tables.

---

## Approach

The raw log contains 30 October records, while Finance reports 22. The
reconciliation applies campaign eligibility first, then handles retries by
campaign family. Standalone campaigns remain event-based, even when a customer
appears more than once.

The detailed checks are in [`investigation_log.md`](investigation_log.md) and
[`sql/02_investigation.sql`](sql/02_investigation.sql).

---

## Reconciliation Bridge

| Step | Target Base | Adjustment | Explanation |
|---|---:|---:|---|
| Naive October communication-log count | 30 | — | Starting point |
| Exclude ineligible campaign 9004 | 26 | -4 | Campaign is still `approval_awaiting` |
| Deduplicate retry family 9001 | 23 | -3 | C2 and C3 have multiple attempts within the same retry chain |
| Deduplicate retry family 9201 | 22 | -1 | D1 has a retry attempt |
| Preserve standalone campaign 9101 | 22 | 0 | Repeated C20 sends are legitimate separate events |
| **Final target_base** | **22** | | **Matches Finance** |

```text
30 raw communication rows
    - 4 ineligible campaign rows
    - 3 retry duplicates in family 9001
    - 1 retry duplicate in family 9201
    = 22
```

---

## Campaign-Level Validation

| Root Campaign | Type | Eligible Attempts | Target Base |
|---|---|---:|---:|
| 9001 | Retry family | 13 | 10 |
| 9101 | Standalone | 7 | 7 |
| 9201 | Retry family | 6 | 5 |
| **Total** | | **26** | **22** |

---

## Final SQL

The final reconciliation query is available in [`sql/03_final_reconciliation.sql`](sql/03_final_reconciliation.sql).

The query:

1. Builds the campaign hierarchy recursively.
2. Filters to reportable communication-log rows.
3. Groups records by root campaign.
4. Counts distinct customers for retry families.
5. Counts individual events for standalone campaigns.
6. Returns Finance's target base of **22**.

---

## Result

**Finance target_base = 22**

The reconciliation explains the full gap:

**30 − 4 − 3 − 1 = 22**

The final SQL independently reproduces the Finance number. See
[`investigation_log.md`](investigation_log.md) for the supporting checks.
