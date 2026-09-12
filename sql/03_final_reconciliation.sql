-- Final reconciliation of Finance target_base for:
-- Merchant 501
-- October 2026
-- Communication type 2

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
),


-- Keep only reportable communication records

eligible_logs AS (

    SELECT
        cl.id,
        cl.customer_id,
        ct.root_campaign_id
    FROM communication_log cl
    JOIN campaign_tree ct
        ON cl.communication_id = ct.campaign_id
    JOIN campaign c
        ON cl.communication_id = c.id
    WHERE cl.merchant_id = 501
      AND cl.communication_type = '2'
      AND cl.sent_time >= '2026-10-01'
      AND cl.sent_time < '2026-11-01'
      AND c.creation_status IN (
          'approved',
          'aborted',
          'resumed',
          'stopped'
      )
      AND c.processing_status = 'processed'
),


-- Classify each root as retry family or standalone

root_types AS (

    SELECT
        r.id AS root_campaign_id,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM campaign child
                WHERE child.parent_id = r.id
            )
            THEN 'retry_family'
            ELSE 'standalone'
        END AS communication_kind
    FROM campaign r
    WHERE r.parent_id IS NULL
),

-- Apply target_base counting rule

reconciled AS (

    SELECT
        rt.root_campaign_id,
        rt.communication_kind,
        COUNT(el.id) AS eligible_attempts,

        CASE
            WHEN rt.communication_kind = 'retry_family'
                THEN COUNT(DISTINCT el.customer_id)
            ELSE COUNT(el.id)
        END AS target_base

    FROM root_types rt

    LEFT JOIN eligible_logs el
        ON rt.root_campaign_id = el.root_campaign_id

    GROUP BY
        rt.root_campaign_id,
        rt.communication_kind
)


-- Final result
SELECT
    SUM(target_base) AS target_base
FROM reconciled;