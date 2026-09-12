-- Baseline:
-- Count all October communication-log records for merchant 501
-- where communication_type = '2'.

SELECT
    COUNT(*) AS naive_target_base
FROM communication_log
WHERE merchant_id = 501
  AND communication_type = '2'
  AND sent_time >= '2026-10-01'
  AND sent_time < '2026-11-01';