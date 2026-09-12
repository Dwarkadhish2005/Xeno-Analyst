# Investigation Log — Comm-Log Send Reconciliation

## Objective

Reproduce Finance's `target_base` of 22 for merchant 501 for October 2026 across communication type `2` campaigns.

The investigation started from the raw communication-log count without assuming the reason for the gap.

---

## 1. Baseline — naive communication-log count

### Question

How many communication-log records exist for merchant 501 in October 2026 for communication type `2`?

### Test

Count all matching rows in `communication_log`.

### Result

**30 rows**

### Interpretation

This was the most direct/raw interpretation of the metric and was used as the starting point for the reconciliation.

Finance target:

**22**

Initial gap:

**30 - 22 = 8**

---

## 2. Campaign reporting eligibility

### Question

Are all campaigns represented in the communication log eligible for official reporting?

### Test

Reviewed campaign `creation_status` and `processing_status` against the reporting eligibility rule:

- `creation_status` must be one of:
  - `approved`
  - `aborted`
  - `resumed`
  - `stopped`
- `processing_status` must be `processed`

### Observation

Campaign `9004`:

- `creation_status = approval_awaiting`
- `processing_status = processed`
- communication-log rows = 4

The campaign had communication records even though its creation workflow had not cleared approval.

### Adjustment

**30 → 26**

Adjustment:

**-4**

### Reason

The four communication records belonging to campaign 9004 are not reportable because the campaign is still `approval_awaiting`.

---

## 3. Retry-family investigation

### Question

Could repeated communication-log records represent retries of the same underlying communication rather than separate target-base customers?

### Test

Built the campaign hierarchy using a recursive CTE and grouped eligible communication records by root campaign and customer.

### Observation

The retry structure is:

- `9001 → 9002 → 9003`
- `9001 → 9004`
- `9201 → 9202`

Campaign 9004 was already excluded because it is ineligible.

Within the eligible 9001 retry family:

- C2 appears in campaigns 9001 and 9002.
- C3 appears in campaigns 9001, 9002 and 9003.

Therefore:

- 13 eligible attempts
- 10 distinct customers
- reduction of 3

### Adjustment

**26 → 23**

Adjustment:

**-3**

### Reason

Multiple attempts within the same retry chain represent the same underlying customer communication and should be counted once.

---

## 4. Second retry family

### Observation

Within the 9201 retry family:

- D1 appears in 9201 as a failed attempt.
- D1 appears again in 9202 as a delivered attempt.

Therefore:

- 6 eligible attempts
- 5 distinct customers
- reduction of 1

### Adjustment

**23 → 22**

Adjustment:

**-1**

### Reason

The second attempt is part of the same retry chain and therefore does not create another target-base customer.

---

## 5. Standalone campaign validation

### Question

Should repeated customers always be deduplicated?

### Observation

Campaign 9101 is a standalone campaign with no retry relationship.

Customer C20 appears twice in the same campaign:

- 9101 → C20
- 9101 → C20

There are 7 eligible communication rows and 6 distinct customers.

### Decision

Do **not** deduplicate C20.

The data dictionary states that a standalone communication can legitimately contain multiple sends to the same customer, with each send treated as a separate event.

Therefore:

**9101 = 7 target-base events**

rather than 6.

### Adjustment

**0**

This prevented an incorrect additional reduction.

---

## 6. Date-scope validation

### Question

Could records outside October be affecting the baseline?

### Test

Checked the minimum and maximum `sent_time` and counted records satisfying the October date condition.

### Result

- Earliest send: `2026-10-03 10:00:00`
- Latest send: `2026-10-20 10:00:00`
- Total merchant 501 rows: 30
- October rows: 30

### Decision

All 30 records are within the requested October period.

### Adjustment

**0**

---

## 7. Communication type validation

### Question

Are there communication records outside the requested communication type?

### Result

All 30 merchant 501 records have:

`communication_type = '2'`

### Adjustment

**0**

The communication-type filter therefore does not change the baseline.

---

## 8. Delivery-status validation

### Question

Should failed communication attempts be excluded from the target-base calculation?

### Result

The data contains:

- 26 delivered records
- 4 failed records

### Decision

Failed records were not automatically excluded.

The data dictionary describes status `1100` as a soft failure and explains that failed customers may subsequently be retried through another campaign.

The customer-level investigation confirms this behavior:

- C2: failed → delivered
- C3: failed → failed → delivered
- D1: failed → delivered

Therefore, delivery status is part of the retry history rather than a standalone exclusion rule.

### Adjustment

**0**

---

## 9. Join integrity validation

### Question

Could missing campaign references or duplicate campaign IDs distort the reconciliation?

### Tests

Checked for communication-log records with no matching campaign and duplicate campaign IDs.

### Results

- Orphan communication records: **0**
- Duplicate campaign IDs: **0**

### Decision

The `communication_log.communication_id → campaign.id` relationship is safe for the reconciliation.

### Adjustment

**0**

---

# Final Reconciliation Bridge

| Step | Target Base | Adjustment | Reason |
|------|------------:|-----------:|--------|
| Naive October communication-log count | 30 | — | Starting point |
| Exclude ineligible campaign 9004 | 26 | -4 | Campaign is `approval_awaiting` |
| Deduplicate retry family 9001 | 23 | -3 | C2 and C3 have repeated retry attempts |
| Deduplicate retry family 9201 | 22 | -1 | D1 has a retry attempt |
| Preserve standalone campaign 9101 | 22 | 0 | Repeated C20 sends are legitimate separate events |
| **Final target_base** | **22** | | Matches Finance |

## Final result

**Finance target_base = 22**

The final SQL independently reproduces the result as `22`.