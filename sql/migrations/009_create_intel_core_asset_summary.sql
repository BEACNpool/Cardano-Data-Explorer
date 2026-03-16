-- 009_create_intel_core_asset_summary.sql
-- Materialized view: one row per native asset with supply, mint/burn history, and holder count.
--
-- Depends on: public.multi_asset, public.ma_tx_mint, public.ma_tx_out, public.tx_out, public.tx, public.block
-- Rollback: DROP MATERIALIZED VIEW IF EXISTS intel_core.asset_summary CASCADE;

BEGIN;

CREATE MATERIALIZED VIEW IF NOT EXISTS intel_core.asset_summary AS
WITH mint_history AS (
    SELECT
        mtm.ident,
        SUM(mtm.quantity) FILTER (WHERE mtm.quantity > 0) AS total_minted,
        SUM(ABS(mtm.quantity)) FILTER (WHERE mtm.quantity < 0) AS total_burned,
        SUM(mtm.quantity) AS current_supply,
        COUNT(*) FILTER (WHERE mtm.quantity > 0) AS mint_tx_count,
        COUNT(*) FILTER (WHERE mtm.quantity < 0) AS burn_tx_count,
        MIN(b.time) AS first_mint_time,
        MAX(b.time) AS last_activity_time,
        MIN(b.epoch_no) AS first_mint_epoch
    FROM ma_tx_mint mtm
    JOIN tx ON tx.id = mtm.tx_id
    JOIN block b ON b.id = tx.block_id
    GROUP BY mtm.ident
),
holder_counts AS (
    SELECT
        mto.ident,
        COUNT(DISTINCT txo.address) AS holder_count,
        SUM(mto.quantity) AS circulating_quantity
    FROM ma_tx_out mto
    JOIN tx_out txo ON txo.id = mto.tx_out_id
    WHERE txo.consumed_by_tx_id IS NULL  -- only unspent outputs
    GROUP BY mto.ident
)
SELECT
    ma.id AS asset_id,
    encode(ma.policy, 'hex') AS policy_id,
    encode(ma.name, 'hex') AS asset_name_hex,
    convert_from(ma.name, 'UTF8') AS asset_name,
    ma.fingerprint,
    COALESCE(mh.current_supply, 0) AS current_supply,
    COALESCE(mh.total_minted, 0) AS total_minted,
    COALESCE(mh.total_burned, 0) AS total_burned,
    COALESCE(mh.mint_tx_count, 0) AS mint_tx_count,
    COALESCE(mh.burn_tx_count, 0) AS burn_tx_count,
    COALESCE(hc.holder_count, 0) AS holder_count,
    mh.first_mint_time,
    mh.last_activity_time,
    mh.first_mint_epoch
FROM multi_asset ma
LEFT JOIN mint_history mh ON mh.ident = ma.id
LEFT JOIN holder_counts hc ON hc.ident = ma.id
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_asset_summary_id
    ON intel_core.asset_summary (asset_id);

CREATE INDEX IF NOT EXISTS idx_asset_summary_policy
    ON intel_core.asset_summary (policy_id);

CREATE INDEX IF NOT EXISTS idx_asset_summary_fingerprint
    ON intel_core.asset_summary (fingerprint);

CREATE INDEX IF NOT EXISTS idx_asset_summary_holders
    ON intel_core.asset_summary (holder_count DESC);

INSERT INTO intel_meta.view_registry (schema_name, view_name, description, refresh_order)
VALUES ('intel_core', 'asset_summary', 'One row per native asset: supply, mints, burns, holder count', 70)
ON CONFLICT (schema_name, view_name) DO NOTHING;

COMMIT;
