# Comm-Log Send Reconciliation

## Xeno Data Analyst Internship Assignment

Reconciliation of Finance's `target_base` metric for:

- **Merchant:** 501
- **Period:** October 2026
- **Communication type:** `2`
- **Finance target:** 22

---

## Objective

Reproduce Finance's reported `target_base` of **22** from the raw campaign and communication-log data and identify the reasons for the difference between a naive count and the Finance number.

The analysis was performed in SQLite using the provided `campaign` and `communication_log` tables.

---

## Approach

I started with the most direct count of communication-log records and then investigated the gap through:

1. Campaign reporting eligibility
2. Campaign retry hierarchy
3. Customer-level retry attempts
4. Standalone campaign behavior
5. Date and communication-type scope
6. Delivery-status distribution
7. Join and key integrity

The investigation deliberately tested potential explanations rather than assuming the Finance target definition upfront.

Detailed investigation notes are available in [`investigation_log.md`](investigation_log.md).

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

### Reconciliation

```text
30 raw communication rows
    - 4 ineligible campaign rows
    - 3 retry duplicates in family 9001
    - 1 retry duplicate in family 9201
    = 22