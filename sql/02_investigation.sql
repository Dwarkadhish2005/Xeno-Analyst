-- Xeno Data Analyst Assignment
-- Comm-Log Send Reconciliation
--
-- Investigation queries used to understand the gap
-- between the naive count (30) and Finance target_base (22).


-- ============================================================
-- 1. Campaign population and reporting eligibility
-- ============================================================

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
-- 2. Communication rows by campaign
-- ============================================================

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
-- 3. Retry-family analysis
-- ============================================================

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
-- 4. Customer-level retry inspection
-- ============================================================

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
    ON c.id = ct.campaign_id
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
-- 5. Date-scope validation
-- ============================================================

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
-- 6. Communication type and delivery status distribution
-- ============================================================

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
-- 7. Referential integrity: orphan communication records
-- ============================================================

SELECT
    COUNT(*) AS orphan_rows
FROM communication_log cl
LEFT JOIN campaign c
    ON cl.communication_id = c.id
WHERE c.id IS NULL;


-- ============================================================
-- 8. Campaign ID uniqueness
-- ============================================================

SELECT
    COUNT(*) AS duplicate_campaign_ids
FROM (
    SELECT id
    FROM campaign
    GROUP BY id
    HAVING COUNT(*) > 1
);