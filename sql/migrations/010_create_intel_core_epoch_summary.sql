-- 010_create_intel_core_epoch_summary.sql
-- Materialized view: one row per epoch with aggregate network stats.
--
-- Depends on: public.block, public.tx, public.ada_pots, public.epoch_stake
-- Rollback: DROP MATERIALIZED VIEW IF EXISTS intel_core.epoch_summary CASCADE;

BEGIN;

CREATE MATERIALIZED VIEW IF NOT EXISTS intel_core.epoch_summary AS
WITH epoch_blocks AS (
    SELECT
        b.epoch_no,
        COUNT(*) AS block_count,
        SUM(b.tx_count) AS tx_count,
        SUM(b.size) AS total_block_size,
        MIN(b.time) AS epoch_start,
        MAX(b.time) AS epoch_end,
        MIN(b.slot_no) AS first_slot,
        MAX(b.slot_no) AS last_slot
    FROM block b
    WHERE b.epoch_no IS NOT NULL
    GROUP BY b.epoch_no
),
epoch_fees AS (
    SELECT
        b.epoch_no,
        SUM(tx.fee) AS total_fees,
        SUM(tx.out_sum) AS total_output
    FROM tx
    JOIN block b ON b.id = tx.block_id
    WHERE b.epoch_no IS NOT NULL
    GROUP BY b.epoch_no
),
epoch_staking AS (
    SELECT
        es.epoch_no,
        SUM(es.amount) AS total_staked,
        COUNT(DISTINCT es.addr_id) AS staker_count,
        COUNT(DISTINCT es.pool_id) AS active_pool_count
    FROM epoch_stake es
    GROUP BY es.epoch_no
)
SELECT
    eb.epoch_no,
    eb.block_count,
    eb.tx_count,
    eb.total_block_size,
    eb.epoch_start,
    eb.epoch_end,
    eb.first_slot,
    eb.last_slot,
    COALESCE(ef.total_fees, 0) AS total_fees,
    COALESCE(ef.total_output, 0) AS total_output,
    ap.utxo AS utxo_supply,
    ap.treasury,
    ap.reserves,
    ap.rewards AS reward_pot,
    COALESCE(est.total_staked, 0) AS total_staked,
    COALESCE(est.staker_count, 0) AS staker_count,
    COALESCE(est.active_pool_count, 0) AS active_pool_count
FROM epoch_blocks eb
LEFT JOIN epoch_fees ef ON ef.epoch_no = eb.epoch_no
LEFT JOIN ada_pots ap ON ap.epoch_no = eb.epoch_no
LEFT JOIN epoch_staking est ON est.epoch_no = eb.epoch_no
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_epoch_summary_no
    ON intel_core.epoch_summary (epoch_no);

INSERT INTO intel_meta.view_registry (schema_name, view_name, description, refresh_order)
VALUES ('intel_core', 'epoch_summary', 'One row per epoch: blocks, txs, fees, staking, ada pots', 80)
ON CONFLICT (schema_name, view_name) DO NOTHING;

COMMIT;
