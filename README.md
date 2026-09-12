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

## Analytical Approach

I treated this as a reconciliation problem rather than trying to write a query that simply returns 22.

The starting question was:

> **Why does the most obvious communication-log count disagree with Finance's 22?**

I tested possible explanations in sequence, keeping both adjustments and zero-impact checks in the investigation record:

1. Establish the raw baseline.
2. Check campaign reporting eligibility.
3. Investigate the campaign retry hierarchy.
4. Validate retry behavior at the customer level.
5. Challenge the deduplication assumption using a standalone campaign.
6. Validate date and communication-type scope.
7. Check delivery status behavior.
8. Check join and key integrity.

The detailed hypothesis trail and SQL tests are in [`investigation_log.md`](investigation_log.md) and [`sql/02_investigation.sql`](sql/02_investigation.sql).

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

## Investigation Process

### 1. Baseline

The naive count of October communication-log records for merchant 501 and communication type `2` is **30**. Finance reports **22**, leaving an unexplained gap of **8**.

### 2. Eligibility hypothesis

I checked whether every campaign represented in the log was eligible for reporting. Campaign `9004` was still `approval_awaiting` even though it had four communication-log rows.

This reduced the reportable population from **30 to 26**.

### 3. Retry hypothesis

I then checked whether repeated rows represented retry attempts rather than independent underlying communications. The campaign hierarchy contains chains such as `9001 → 9002 → 9003` and `9201 → 9202`.

Within the eligible `9001` family, C2 was attempted twice and C3 three times. The family therefore has **13 attempts but 10 distinct customers**, producing a reduction of **3**.

The `9201` family has **6 attempts but 5 distinct customers**, producing a further reduction of **1**.

### 4. Challenge: repeated customer does not always mean duplicate

I specifically checked whether the retry rule should be applied globally. Campaign `9101` is standalone, but customer C20 appears twice in it. Those are two separate send events, not a retry chain.

Therefore I did **not** deduplicate C20. A global `COUNT(DISTINCT customer_id)` would incorrectly reduce the answer further.

### 5. Other hypotheses ruled out

Several checks produced no adjustment, but they were retained because they ruled out plausible causes:

- All 30 merchant records fall within October 2026.
- All 30 records have communication type `2`.
- Failed delivery records are part of observed retry sequences and are not automatically excluded.
- There are no orphan communication records.
- Campaign IDs are unique, so the campaign join does not introduce multiplication.

### 6. An investigation correction

During the retry analysis, an initial approach considered eligibility at the root-family level. That would have incorrectly included the `9004` branch because its root `9001` was eligible.

I corrected this by separating two concepts:

- **Hierarchy determines the retry family.**
- **Campaign eligibility determines which log rows are reportable.**

This ensures the ineligible `9004` records remain excluded while the eligible `9001` family is still treated as a retry family.

---

## Key Analytical Insight

The important distinction is not simply **"duplicate customer vs. unique customer."** The counting grain depends on the campaign relationship:

- **Retry family:** count distinct customers across the full retry chain.
- **Standalone campaign:** each send remains a separate event, even if the customer appears more than once.

This is why a global `COUNT(DISTINCT customer_id)` is not sufficient.

---

## Surprising Observation

A communication-log row does not necessarily mean a reportable send: campaign `9004` already had four log records while its creation status was still `approval_awaiting`. At the same time, a repeated customer in a standalone campaign can be a legitimate separate event. These two behaviors make the raw log more nuanced than a simple one-row-one-target count.

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

It:

1. Builds the campaign hierarchy recursively.
2. Filters to reportable communication-log rows.
3. Groups records by root campaign.
4. Counts distinct customers for retry families.
5. Counts individual events for standalone campaigns.
6. Returns Finance's target base of **22**.

---

## Repository Structure

```text
Xeno-Analyst/
├── data/
│   ├── campaign.csv
│   ├── communication_log.csv
│   ├── comm_log.db
│   └── README.md
├── sql/
│   ├── 01_baseline.sql
│   ├── 02_investigation.sql
│   └── 03_final_reconciliation.sql
├── investigation_log.md
├── generate_dataset.py
├── README.md
└── .gitignore
```

---

## Result

**Finance target_base = 22**

The reconciliation explains the full gap:

**30 − 4 − 3 − 1 = 22**

The final SQL independently reproduces the Finance number.
