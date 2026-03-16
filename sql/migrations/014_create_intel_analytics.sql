-- 014_create_intel_analytics.sql
-- Materialized views for network-wide analytics and trend tracking.
--
-- Rollback: DROP MATERIALIZED VIEW IF EXISTS intel_analytics.daily_metrics,
--           intel_analytics.pool_epoch_metrics, intel_analytics.delegation_concentration CASCADE;

BEGIN;

--------------------------------------------------------------------
-- DAILY METRICS: one row per day with tx count, volume, fees, active addrs
--------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS intel_analytics.daily_metrics AS
SELECT
    DATE(b.time) AS day,
    COUNT(DISTINCT tx.id) AS tx_count,
    SUM(tx.out_sum) AS total_output,
    SUM(tx.fee) AS total_fees,
    AVG(tx.fee)::BIGINT AS avg_fee,
    COUNT(DISTINCT tx.id) FILTER (WHERE tx.script_size > 0) AS script_tx_count,
    SUM(b.size) AS total_block_size,
    COUNT(DISTINCT b.id) AS block_count
FROM block b
JOIN tx ON tx.block_id = b.id
WHERE b.time IS NOT NULL
GROUP BY DATE(b.time)
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_metrics_day
    ON intel_analytics.daily_metrics (day);

--------------------------------------------------------------------
-- POOL EPOCH METRICS: per pool per epoch performance
--------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS intel_analytics.pool_epoch_metrics AS
SELECT
    ph.view AS pool_id,
    es.epoch_no,
    SUM(es.amount) AS total_stake,
    COUNT(DISTINCT es.addr_id) AS delegator_count,
    COALESCE(bm.blocks_minted, 0) AS blocks_minted
FROM epoch_stake es
JOIN pool_hash ph ON ph.id = es.pool_id
LEFT JOIN (
    SELECT
        sl.pool_hash_id,
        b.epoch_no,
        COUNT(*) AS blocks_minted
    FROM block b
    JOIN slot_leader sl ON sl.id = b.slot_leader_id
    WHERE sl.pool_hash_id IS NOT NULL
    GROUP BY sl.pool_hash_id, b.epoch_no
) bm ON bm.pool_hash_id = es.pool_id AND bm.epoch_no = es.epoch_no
GROUP BY ph.view, es.epoch_no, bm.blocks_minted
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pool_epoch_metrics_pk
    ON intel_analytics.pool_epoch_metrics (pool_id, epoch_no);

CREATE INDEX IF NOT EXISTS idx_pool_epoch_metrics_epoch
    ON intel_analytics.pool_epoch_metrics (epoch_no);

CREATE INDEX IF NOT EXISTS idx_pool_epoch_metrics_stake
    ON intel_analytics.pool_epoch_metrics (total_stake DESC);

--------------------------------------------------------------------
-- DELEGATION CONCENTRATION: Nakamoto-style concentration per epoch
--------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS intel_analytics.delegation_concentration AS
WITH ranked AS (
    SELECT
        epoch_no,
        pool_id,
        total_stake,
        SUM(total_stake) OVER (PARTITION BY epoch_no ORDER BY total_stake DESC) AS cumulative_stake,
        SUM(total_stake) OVER (PARTITION BY epoch_no) AS epoch_total_stake,
        ROW_NUMBER() OVER (PARTITION BY epoch_no ORDER BY total_stake DESC) AS rank
    FROM intel_analytics.pool_epoch_metrics
)
SELECT
    epoch_no,
    -- Nakamoto coefficient: min pools to reach 51%
    MIN(rank) FILTER (WHERE cumulative_stake >= epoch_total_stake * 0.51) AS nakamoto_coefficient,
    -- Top-N concentration
    (SUM(total_stake) FILTER (WHERE rank <= 10) * 100.0 /
        NULLIF(MAX(epoch_total_stake), 0))::NUMERIC(5,2) AS top10_pct,
    (SUM(total_stake) FILTER (WHERE rank <= 25) * 100.0 /
        NULLIF(MAX(epoch_total_stake), 0))::NUMERIC(5,2) AS top25_pct,
    (SUM(total_stake) FILTER (WHERE rank <= 50) * 100.0 /
        NULLIF(MAX(epoch_total_stake), 0))::NUMERIC(5,2) AS top50_pct,
    COUNT(DISTINCT pool_id) AS total_pools
FROM ranked
GROUP BY epoch_no
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_deleg_concentration_epoch
    ON intel_analytics.delegation_concentration (epoch_no);

-- Register
INSERT INTO intel_meta.view_registry (schema_name, view_name, description, refresh_order) VALUES
    ('intel_analytics', 'daily_metrics', 'Daily network metrics: tx count, volume, fees', 200),
    ('intel_analytics', 'pool_epoch_metrics', 'Per-pool per-epoch: stake, delegators, blocks', 210),
    ('intel_analytics', 'delegation_concentration', 'Nakamoto coefficient and top-N concentration per epoch', 220)
ON CONFLICT (schema_name, view_name) DO NOTHING;

COMMIT;
