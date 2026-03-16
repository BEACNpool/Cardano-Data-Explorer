-- 003_create_intel_core_address_summary.sql
-- Materialized view: one row per address with balance, tx counts, first/last activity.
-- This is the most common explorer query — "show me everything about this address."
--
-- Depends on: public.tx_out, public.tx_in, public.tx, public.block, public.stake_address
-- Rollback: DROP MATERIALIZED VIEW IF EXISTS intel_core.address_summary CASCADE;

BEGIN;

CREATE MATERIALIZED VIEW IF NOT EXISTS intel_core.address_summary AS
WITH addr_outputs AS (
    SELECT
        txo.address,
        txo.stake_address_id,
        COUNT(*) AS total_output_count,
        SUM(txo.value) AS total_received,
        MIN(b.time) AS first_seen,
        MAX(b.time) AS last_seen,
        MIN(b.epoch_no) AS first_epoch,
        MAX(b.epoch_no) AS last_epoch
    FROM tx_out txo
    JOIN tx ON tx.id = txo.tx_id
    JOIN block b ON b.id = tx.block_id
    GROUP BY txo.address, txo.stake_address_id
),
addr_spent AS (
    SELECT
        txo.address,
        COUNT(*) AS total_input_count,
        SUM(txo.value) AS total_spent
    FROM tx_out txo
    WHERE txo.consumed_by_tx_id IS NOT NULL
    GROUP BY txo.address
),
addr_unspent AS (
    SELECT
        txo.address,
        SUM(txo.value) AS current_balance,
        COUNT(*) AS utxo_count
    FROM tx_out txo
    WHERE txo.consumed_by_tx_id IS NULL
    GROUP BY txo.address
)
SELECT
    ao.address,
    sa.view AS stake_address,
    COALESCE(au.current_balance, 0) AS current_balance,
    ao.total_received,
    COALESCE(asp.total_spent, 0) AS total_spent,
    ao.total_output_count,
    COALESCE(asp.total_input_count, 0) AS total_input_count,
    COALESCE(au.utxo_count, 0) AS utxo_count,
    ao.first_seen,
    ao.last_seen,
    ao.first_epoch,
    ao.last_epoch
FROM addr_outputs ao
LEFT JOIN addr_spent asp ON asp.address = ao.address
LEFT JOIN addr_unspent au ON au.address = ao.address
LEFT JOIN stake_address sa ON sa.id = ao.stake_address_id
WITH NO DATA;

-- Unique index required for REFRESH CONCURRENTLY
CREATE UNIQUE INDEX IF NOT EXISTS idx_address_summary_addr
    ON intel_core.address_summary (address);

CREATE INDEX IF NOT EXISTS idx_address_summary_stake
    ON intel_core.address_summary (stake_address)
    WHERE stake_address IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_address_summary_balance
    ON intel_core.address_summary (current_balance DESC);

-- Register in view_registry
INSERT INTO intel_meta.view_registry (schema_name, view_name, description, refresh_order)
VALUES ('intel_core', 'address_summary', 'One row per address: balance, tx counts, first/last seen', 10)
ON CONFLICT (schema_name, view_name) DO NOTHING;

COMMIT;
