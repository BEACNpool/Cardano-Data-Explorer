-- 006_create_intel_core_pool_summary.sql
-- Materialized view: one row per stake pool with registration, delegation, and block info.
--
-- Depends on: public.pool_hash, public.pool_update, public.pool_retire,
--             public.pool_offline_data, public.epoch_stake, public.block, public.slot_leader
-- Rollback: DROP MATERIALIZED VIEW IF EXISTS intel_core.pool_summary CASCADE;

BEGIN;

CREATE MATERIALIZED VIEW IF NOT EXISTS intel_core.pool_summary AS
WITH latest_update AS (
    SELECT DISTINCT ON (pu.hash_id)
        pu.hash_id,
        pu.pledge,
        pu.margin,
        pu.fixed_cost,
        pu.active_epoch_no AS update_active_epoch,
        pu.registered_tx_id
    FROM pool_update pu
    ORDER BY pu.hash_id, pu.registered_tx_id DESC
),
retirement AS (
    SELECT DISTINCT ON (pr.hash_id)
        pr.hash_id,
        pr.retiring_epoch
    FROM pool_retire pr
    ORDER BY pr.hash_id, pr.announced_tx_id DESC
),
latest_epoch_stake AS (
    SELECT
        es.pool_id,
        es.epoch_no,
        SUM(es.amount) AS live_stake,
        COUNT(DISTINCT es.addr_id) AS delegator_count
    FROM epoch_stake es
    WHERE es.epoch_no = (SELECT MAX(epoch_no) FROM epoch_stake)
    GROUP BY es.pool_id, es.epoch_no
),
blocks_minted AS (
    SELECT
        sl.pool_hash_id,
        COUNT(*) AS total_blocks
    FROM block b
    JOIN slot_leader sl ON sl.id = b.slot_leader_id
    WHERE sl.pool_hash_id IS NOT NULL
    GROUP BY sl.pool_hash_id
),
pool_meta AS (
    SELECT DISTINCT ON (pod.pool_id)
        pod.pool_id AS hash_id,
        pod.ticker_name,
        pod.json->>'name' AS pool_name,
        pod.json->>'homepage' AS homepage,
        pod.json->>'description' AS pool_description
    FROM pool_offline_data pod
    ORDER BY pod.pool_id, pod.id DESC
)
SELECT
    ph.view AS pool_id,
    ph.hash_raw AS pool_hash,
    pm.ticker_name,
    pm.pool_name,
    pm.homepage,
    pm.pool_description,
    lu.pledge,
    lu.margin,
    lu.fixed_cost,
    COALESCE(les.live_stake, 0) AS live_stake,
    COALESCE(les.delegator_count, 0) AS delegator_count,
    les.epoch_no AS stake_epoch,
    COALESCE(bm.total_blocks, 0) AS total_blocks,
    CASE
        WHEN ret.retiring_epoch IS NOT NULL
             AND ret.retiring_epoch <= les.epoch_no THEN 'retired'
        WHEN lu.hash_id IS NULL THEN 'unknown'
        ELSE 'active'
    END AS status,
    ret.retiring_epoch
FROM pool_hash ph
LEFT JOIN latest_update lu ON lu.hash_id = ph.id
LEFT JOIN retirement ret ON ret.hash_id = ph.id
LEFT JOIN latest_epoch_stake les ON les.pool_id = ph.id
LEFT JOIN blocks_minted bm ON bm.pool_hash_id = ph.id
LEFT JOIN pool_meta pm ON pm.hash_id = ph.id
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pool_summary_id
    ON intel_core.pool_summary (pool_id);

CREATE INDEX IF NOT EXISTS idx_pool_summary_ticker
    ON intel_core.pool_summary (ticker_name)
    WHERE ticker_name IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_pool_summary_stake
    ON intel_core.pool_summary (live_stake DESC);

CREATE INDEX IF NOT EXISTS idx_pool_summary_status
    ON intel_core.pool_summary (status);

INSERT INTO intel_meta.view_registry (schema_name, view_name, description, refresh_order)
VALUES ('intel_core', 'pool_summary', 'One row per pool: stake, delegators, blocks, margin, status', 40)
ON CONFLICT (schema_name, view_name) DO NOTHING;

COMMIT;
