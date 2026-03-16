-- 004_create_intel_core_tx_summary.sql
-- Materialized view: enriched transaction view with resolved inputs, outputs, and metadata.
-- Enables fast tx lookups by hash with full input/output details.
--
-- Depends on: public.tx, public.tx_out, public.tx_in, public.block
-- Rollback: DROP MATERIALIZED VIEW IF EXISTS intel_core.tx_io, intel_core.tx_summary CASCADE;

BEGIN;

-- tx_summary: one row per transaction with block context and fee info
CREATE MATERIALIZED VIEW IF NOT EXISTS intel_core.tx_summary AS
SELECT
    tx.id AS tx_id,
    encode(tx.hash, 'hex') AS tx_hash,
    b.block_no,
    b.epoch_no,
    b.slot_no,
    b.time AS block_time,
    tx.out_sum,
    tx.fee,
    tx.deposit,
    tx.size AS tx_size,
    tx.valid_contract,
    tx.script_size,
    tx.invalid_before,
    tx.invalid_hereafter,
    (SELECT COUNT(*) FROM tx_in ti WHERE ti.tx_in_id = tx.id) AS input_count,
    (SELECT COUNT(*) FROM tx_out txo WHERE txo.tx_id = tx.id) AS output_count
FROM tx
JOIN block b ON b.id = tx.block_id
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_tx_summary_txid
    ON intel_core.tx_summary (tx_id);

CREATE INDEX IF NOT EXISTS idx_tx_summary_hash
    ON intel_core.tx_summary (tx_hash);

CREATE INDEX IF NOT EXISTS idx_tx_summary_block
    ON intel_core.tx_summary (block_no DESC);

CREATE INDEX IF NOT EXISTS idx_tx_summary_epoch
    ON intel_core.tx_summary (epoch_no);

-- tx_io: one row per input or output of a transaction, for detailed lookup
CREATE MATERIALIZED VIEW IF NOT EXISTS intel_core.tx_io AS
-- Outputs
SELECT
    tx.id AS tx_id,
    encode(tx.hash, 'hex') AS tx_hash,
    'output'::TEXT AS direction,
    txo.index AS io_index,
    txo.address,
    sa.view AS stake_address,
    txo.value AS lovelace,
    NULL::BIGINT AS source_tx_id,
    NULL::TEXT AS source_tx_hash
FROM tx_out txo
JOIN tx ON tx.id = txo.tx_id
LEFT JOIN stake_address sa ON sa.id = txo.stake_address_id

UNION ALL

-- Inputs (resolved to the source tx_out they consume)
SELECT
    tx_spend.id AS tx_id,
    encode(tx_spend.hash, 'hex') AS tx_hash,
    'input'::TEXT AS direction,
    ti.tx_out_index AS io_index,
    src_txo.address,
    sa.view AS stake_address,
    src_txo.value AS lovelace,
    src_tx.id AS source_tx_id,
    encode(src_tx.hash, 'hex') AS source_tx_hash
FROM tx_in ti
JOIN tx tx_spend ON tx_spend.id = ti.tx_in_id
JOIN tx_out src_txo ON src_txo.tx_id = ti.tx_out_id AND src_txo.index = ti.tx_out_index
JOIN tx src_tx ON src_tx.id = ti.tx_out_id
LEFT JOIN stake_address sa ON sa.id = src_txo.stake_address_id
WITH NO DATA;

CREATE INDEX IF NOT EXISTS idx_tx_io_txid
    ON intel_core.tx_io (tx_id);

CREATE INDEX IF NOT EXISTS idx_tx_io_hash
    ON intel_core.tx_io (tx_hash);

CREATE INDEX IF NOT EXISTS idx_tx_io_address
    ON intel_core.tx_io (address);

-- Register
INSERT INTO intel_meta.view_registry (schema_name, view_name, description, refresh_order) VALUES
    ('intel_core', 'tx_summary', 'One row per tx: hash, block, epoch, fee, size, io counts', 20),
    ('intel_core', 'tx_io', 'One row per tx input/output: address, value, direction', 21)
ON CONFLICT (schema_name, view_name) DO NOTHING;

COMMIT;
