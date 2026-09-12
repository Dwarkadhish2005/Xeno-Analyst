-- Xeno Data Analyst Assignment
-- Comm-Log Send Reconciliation
--
-- Investigation queries used to explain the gap between the
-- naive communication-log count (30) and Finance target_base (22).
--
-- The sections are intentionally ordered as an investigation:
-- establish the population, test eligibility, investigate retries,
-- challenge the deduplication rule, then validate scope and joins.


-- ============================================================
-- 1. Establish the campaign population and eligibility
-- ============================================================
-- Question: Are all campaigns represented in communication_log
-- actually reportable?

SELECT
    id,
    name,
    parent_id,
    creation_status,
    processing_status,
    CASE
        WHEN creation_status IN (
            'approved',
            'aborted',
            'resumed',
            'stopped'
        )
        AND processing_status = 'processed'
        THEN 'eligible'
        ELSE 'ineligible'
    END AS reporting_eligibility
FROM campaign
ORDER BY id;


-- ============================================================
-- 2. Quantify communication rows contributed by each campaign
-- ============================================================
-- Question: Which campaigns are responsible for the raw count?
-- This makes any status-based adjustment measurable.

SELECT
    c.id AS campaign_id,
    c.name,
    c.parent_id,
    c.creation_status,
    c.processing_status,
    COUNT(cl.id) AS communication_rows
FROM campaign c
LEFT JOIN communication_log cl
    ON c.id = cl.communication_id
GROUP BY
    c.id,
    c.name,
    c.parent_id,
    c.creation_status,
    c.processing_status
ORDER BY c.id;


-- ============================================================
-- 3. Test the retry-family hypothesis
-- ============================================================
-- Question: Could multiple log rows represent retry attempts
-- belonging to one underlying communication?
--
-- A recursive CTE is used because retry chains can be more than
-- one level deep (for example A -> B -> C).
--
-- Eligibility is applied to each campaign contributing log rows,
-- rather than only to the root campaign.

WITH RECURSIVE campaign_tree AS (
    SELECT
        id AS campaign_id,
        id AS root_campaign_id
    FROM campaign
    WHERE parent_id IS NULL

    UNION ALL

    SELECT
        c.id AS campaign_id,
        ct.root_campaign_id
    FROM campaign c
    JOIN campaign_tree ct
        ON c.parent_id = ct.campaign_id
)
SELECT
    ct.root_campaign_id,
    COUNT(cl.id) AS eligible_attempts,
    COUNT(DISTINCT cl.customer_id) AS distinct_customers
FROM campaign_tree ct
JOIN communication_log cl
    ON cl.communication_id = ct.campaign_id
JOIN campaign c
    ON c.id = ct.campaign_id
WHERE c.creation_status IN (
          'approved',
          'aborted',
          'resumed',
          'stopped'
      )
  AND c.processing_status = 'processed'
GROUP BY ct.root_campaign_id
ORDER BY ct.root_campaign_id;


-- ============================================================
-- 4. Inspect retry behavior at customer level
-- ============================================================
-- Question: Is the difference between attempts and distinct
-- customers actually caused by retry sequences?
--
-- This exposes examples such as:
-- C2: 9001 failed -> 9002 delivered
-- C3: 9001 failed -> 9002 failed -> 9003 delivered
-- D1: 9201 failed -> 9202 delivered

WITH RECURSIVE campaign_tree AS (
    SELECT
        id AS campaign_id,
        id AS root_campaign_id
    FROM campaign
    WHERE parent_id IS NULL

    UNION ALL

    SELECT
        c.id AS campaign_id,
        ct.root_campaign_id
    FROM campaign c
    JOIN campaign_tree ct
        ON c.parent_id = ct.campaign_id
)
SELECT
    ct.root_campaign_id,
    cl.customer_id,
    GROUP_CONCAT(
        ct.campaign_id || ':' || cl.delivery_status,
        ' -> '
    ) AS attempts,
    COUNT(*) AS attempt_count
FROM campaign_tree ct
JOIN communication_log cl
    ON cl.communication_id = ct.campaign_id
JOIN campaign c
    ON cl.communication_id = c.id
WHERE c.creation_status IN (
          'approved',
          'aborted',
          'resumed',
          'stopped'
      )
  AND c.processing_status = 'processed'
GROUP BY
    ct.root_campaign_id,
    cl.customer_id
ORDER BY
    ct.root_campaign_id,
    cl.customer_id;


-- ============================================================
-- 5. Challenge the deduplication hypothesis
-- ============================================================
-- Question: Should every repeated customer be deduplicated?
--
-- The standalone campaign 9101 is deliberately inspected separately.
-- C20 appears twice in the same standalone campaign. This is not
-- a retry because no child campaign represents a retry of 9101.
-- Therefore these remain two separate send events.

SELECT
    communication_id AS campaign_id,
    customer_id,
    COUNT(*) AS send_events
FROM communication_log
WHERE merchant_id = 501
  AND communication_id = 9101
GROUP BY communication_id, customer_id
HAVING COUNT(*) > 1;


-- ============================================================
-- 6. Validate the requested date scope
-- ============================================================
-- Question: Could records outside October be contaminating the
-- starting population?

SELECT
    MIN(sent_time) AS earliest_sent_time,
    MAX(sent_time) AS latest_sent_time,
    COUNT(*) AS total_rows,
    SUM(
        CASE
            WHEN sent_time >= '2026-10-01'
             AND sent_time < '2026-11-01'
            THEN 1
            ELSE 0
        END
    ) AS october_rows
FROM communication_log
WHERE merchant_id = 501;


-- ============================================================
-- 7. Validate communication type and delivery status
-- ============================================================
-- Question: Is communication_type filtering out anything, and
-- should failed rows be excluded?

SELECT
    communication_type,
    delivery_status,
    COUNT(*) AS row_count
FROM communication_log
WHERE merchant_id = 501
GROUP BY
    communication_type,
    delivery_status
ORDER BY
    communication_type,
    delivery_status;


-- ============================================================
-- 8. Validate referential integrity
-- ============================================================
-- Question: Could missing campaign references distort the join?

SELECT
    COUNT(*) AS orphan_rows
FROM communication_log cl
LEFT JOIN campaign c
    ON cl.communication_id = c.id
WHERE c.id IS NULL;


-- ============================================================
-- 9. Validate campaign-key uniqueness
-- ============================================================
-- Question: Could duplicate campaign IDs create join multiplication?

SELECT
    COUNT(*) AS duplicate_campaign_ids
FROM (
    SELECT id
    FROM campaign
    GROUP BY id
    HAVING COUNT(*) > 1
);