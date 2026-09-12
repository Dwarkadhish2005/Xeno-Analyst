# Investigation Log — Comm-Log Send Reconciliation

## Objective

Reproduce Finance's `target_base` of **22** for merchant 501 for October 2026 across communication type `2` campaigns.

I intentionally started from the raw communication-log count without assuming why Finance's number was lower. Each step below records the question being tested, what the data showed, and whether the result changed the reconciliation.

---

## Investigation mindset

The starting question was not **"How do I get 22?"** but:

> **"Why does the most obvious count disagree with Finance's 22?"**

I treated the difference as a reconciliation problem and tested several possible sources of mismatch:

1. Reporting eligibility
2. Retry relationships
3. Customer-level duplicate attempts
4. Standalone repeated sends
5. Date and communication-type scope
6. Delivery status
7. Join/key integrity

Some checks produced an adjustment; others produced **zero adjustment** but were retained because they ruled out plausible explanations.

---

## 1. Baseline — naive communication-log count

### Question

How many communication-log records exist for merchant 501 in October 2026 for communication type `2`?

### Test

Count all matching rows in `communication_log`.

### Result

**30 rows**

Finance target:

**22**

Initial gap:

**30 - 22 = 8**

### Interpretation

This is the most direct interpretation of "number of sends" at the raw-log level. Because it does not match Finance, the next step is to determine whether every raw row is reportable and whether multiple rows can represent the same underlying communication.

---

## 2. Hypothesis: some logged campaigns may not be reportable

### Question

Are all campaigns represented in `communication_log` eligible for official reporting?

### Test

Reviewed `creation_status` and `processing_status` for every campaign and counted communication rows by campaign.

The reporting gate requires a finalized creation status (`approved`, `aborted`, `resumed`, or `stopped`) **and** `processing_status = 'processed'`.

### Observation

Campaign `9004` had:

- `creation_status = approval_awaiting`
- `processing_status = processed`
- **4 communication-log rows**

This was an important finding: communication-log rows can exist before the campaign becomes reportable.

### Adjustment

**30 → 26**

Adjustment:

**-4**

### Decision

Exclude campaign 9004's four records from the reportable population.

---

## 3. Hypothesis: retry attempts are being counted as separate communications

### Question

Could multiple communication-log rows belong to the same underlying communication because they are retries?

### Test

Followed `campaign.parent_id` recursively so that a chain such as `9001 → 9002 → 9003` is treated as one retry family.

I also applied campaign eligibility to each contributing campaign rather than assuming that a root campaign's status automatically makes every child reportable.

### Important intermediate check

An initial root-level eligibility interpretation would have pulled the ineligible `9004` branch into the `9001` family. That was rejected after checking campaign-level eligibility.

This changed the reasoning from:

> "If the root is eligible, include the whole tree."

to:

> "Use the hierarchy to identify the family, but apply reporting eligibility to each campaign's log rows."

### Result

For eligible records in the `9001` family:

- 13 attempts
- 10 distinct customers

The difference of **3** is explained by:

- C2: `9001 failed → 9002 delivered`
- C3: `9001 failed → 9002 failed → 9003 delivered`

### Adjustment

**26 → 23**

Adjustment:

**-3**

### Decision

Deduplicate customers **within the retry family**, because retries represent repeated attempts at the same underlying communication.

---

## 4. Remaining gap: inspect the second retry family

### Question

After the first retry adjustment, why is the result still one above Finance?

### Test

Inspect the other root campaign with a retry child.

### Observation

For family `9201 → 9202`:

- D1 failed in 9201
- D1 was retried and delivered in 9202
- 6 eligible attempts
- 5 distinct customers

### Adjustment

**23 → 22**

Adjustment:

**-1**

### Decision

The second D1 attempt is another retry of the same underlying communication, so it is counted once within the retry family.

At this point the reconciliation reaches Finance's **22**.

---

## 5. Challenge the deduplication hypothesis with a standalone campaign

### Question

Should every repeated customer be deduplicated globally?

This is a deliberate challenge to the previous conclusion. If the answer were simply `COUNT(DISTINCT customer_id)`, the standalone campaign could also be reduced.

### Test

Inspect campaign `9101`, which has no retry child.

### Observation

Customer C20 appears twice:

- `9101 → C20` on October 10
- `9101 → C20` on October 20

There are **7 communication rows** but only **6 distinct customers**.

### Decision

**Do not deduplicate C20.**

The data dictionary distinguishes a standalone repeated send from a retry. A standalone campaign's repeated customer can represent a separate send event, whereas a retry is explicitly represented by a new campaign linked through `parent_id`.

Therefore:

**9101 contributes 7 events, not 6.**

### Adjustment

**0**

### Why this check matters

Without this check, a global `COUNT(DISTINCT customer_id)` could incorrectly remove one legitimate event and produce **21** instead of Finance's **22**.

This is also why the final logic is not simply "count distinct customers everywhere."

---

## 6. Alternative explanation tested: date scope

### Question

Could records outside October be contaminating the baseline?

### Test

Checked the minimum and maximum `sent_time` for merchant 501 and compared the total merchant rows with the October-scoped count.

### Result

- Earliest send: `2026-10-03 10:00:00`
- Latest send: `2026-10-20 10:00:00`
- Total merchant 501 rows: **30**
- October rows: **30**

### Decision

The date filter is not responsible for the 8-row gap.

### Adjustment

**0**

---

## 7. Alternative explanation tested: communication type

### Question

Could other communication types be mixed into the raw population?

### Result

All 30 merchant 501 records have:

`communication_type = '2'`

### Decision

The communication-type filter is correct but does not reduce the baseline.

### Adjustment

**0**

---

## 8. Alternative explanation tested: delivery status

### Question

Should failed sends be excluded from `target_base`?

### Result

The data contains:

- 26 delivered records
- 4 failed records

The failed records are not arbitrary dead rows: they form the start of the observed retry sequences:

- C2: failed → delivered
- C3: failed → failed → delivered
- D1: failed → delivered

### Decision

Do **not** exclude failed records merely because their delivery status is failed. Delivery status helps explain the retry behavior; it is not itself the reporting exclusion rule.

### Adjustment

**0**

---

## 9. Alternative explanation tested: join/key integrity

### Question

Could broken references or duplicate campaign IDs be creating incorrect joins?

### Tests

Checked for:

- communication-log rows without a matching campaign
- duplicate campaign IDs

### Results

- Orphan communication records: **0**
- Duplicate campaign IDs: **0**

### Decision

There is no evidence that referential integrity is distorting the reconciliation.

### Adjustment

**0**

---

# Final Reconciliation Bridge

| Step | Target Base | Adjustment | Reason |
|------|------------:|-----------:|--------|
| Naive October communication-log count | 30 | — | Starting point |
| Exclude ineligible campaign 9004 | 26 | -4 | Campaign is `approval_awaiting` |
| Deduplicate retry family 9001 | 23 | -3 | C2 and C3 represent repeated attempts within one retry family |
| Deduplicate retry family 9201 | 22 | -1 | D1 was retried from 9201 to 9202 |
| Preserve standalone campaign 9101 | 22 | 0 | C20's repeated sends are legitimate separate events |
| **Final target_base** | **22** | | Matches Finance |

## Final result

**Finance target_base = 22**

The final SQL independently reproduces the result as `22`.

## Key analytical takeaway

The important distinction is not simply **"duplicate customer vs. unique customer."** The counting grain depends on the campaign relationship:

- **Retry family:** deduplicate the customer across the full retry chain.
- **Standalone campaign:** each send remains a separate event, even if the customer appears more than once.

That distinction explains why a global `COUNT(DISTINCT customer_id)` is not sufficient.