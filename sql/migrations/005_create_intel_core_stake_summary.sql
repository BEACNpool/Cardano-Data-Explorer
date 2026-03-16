-- 005_create_intel_core_stake_summary.sql
-- Materialized view: one row per stake address with delegation, reward, and balance info.
--
-- Depends on: public.stake_address, public.delegation, public.reward, public.pool_hash,
--             public.tx_out, public.epoch_stake
-- Rollback: DROP MATERIALIZED VIEW IF EXISTS intel_core.stake_summary CASCADE;

BEGIN;

CREATE MATERIALIZED VIEW IF NOT EXISTS intel_core.stake_summary AS
WITH latest_delegation AS (
    SELECT DISTINCT ON (d.addr_id)
        d.addr_id,
        ph.view AS pool_id,
        d.active_epoch_no AS delegation_epoch,
        b.time AS delegation_time
    FROM delegation d
    JOIN pool_hash ph ON ph.id = d.pool_hash_id
    JOIN tx ON tx.id = d.tx_id
    JOIN block b ON b.id = tx.block_id
    ORDER BY d.addr_id, d.tx_id DESC
),
reward_totals AS (
    SELECT
        r.addr_id,
        SUM(r.amount) AS total_rewards,
        COUNT(*) AS reward_count,
        MAX(r.earned_epoch) AS last_reward_epoch
    FROM reward r
    GROUP BY r.addr_id
),
stake_balance AS (
    SELECT
        txo.stake_address_id,
        SUM(txo.value) AS controlled_balance,
        COUNT(*) AS utxo_count
    FROM tx_out txo
    WHERE txo.consumed_by_tx_id IS NULL
      AND txo.stake_address_id IS NOT NULL
    GROUP BY txo.stake_address_id
)
SELECT
    sa.view AS stake_address,
    sa.hash_raw AS stake_hash,
    COALESCE(sb.controlled_balance, 0) AS controlled_balance,
    COALESCE(sb.utxo_count, 0) AS utxo_count,
    ld.pool_id AS delegated_pool,
    ld.delegation_epoch,
    ld.delegation_time,
    COALESCE(rt.total_rewards, 0) AS total_rewards,
    COALESCE(rt.reward_count, 0) AS reward_count,
    rt.last_reward_epoch,
    (sa.script_hash IS NOT NULL) AS is_script
FROM stake_address sa
LEFT JOIN latest_delegation ld ON ld.addr_id = sa.id
LEFT JOIN reward_totals rt ON rt.addr_id = sa.id
LEFT JOIN stake_balance sb ON sb.stake_address_id = sa.id
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_stake_summary_addr
    ON intel_core.stake_summary (stake_address);

CREATE INDEX IF NOT EXISTS idx_stake_summary_pool
    ON intel_core.stake_summary (delegated_pool)
    WHERE delegated_pool IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_stake_summary_balance
    ON intel_core.stake_summary (controlled_balance DESC);

INSERT INTO intel_meta.view_registry (schema_name, view_name, description, refresh_order)
VALUES ('intel_core', 'stake_summary', 'One row per stake address: balance, delegation, rewards', 30)
ON CONFLICT (schema_name, view_name) DO NOTHING;

COMMIT;
