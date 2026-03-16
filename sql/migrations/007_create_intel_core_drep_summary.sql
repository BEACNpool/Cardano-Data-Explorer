-- 007_create_intel_core_drep_summary.sql
-- Materialized view: one row per DRep with voting power, delegator count, and vote history.
--
-- Depends on: public.drep_hash, public.drep_registration, public.drep_distribution,
--             public.delegation_vote, public.voting_procedure
-- Rollback: DROP MATERIALIZED VIEW IF EXISTS intel_core.drep_summary CASCADE;

BEGIN;

CREATE MATERIALIZED VIEW IF NOT EXISTS intel_core.drep_summary AS
WITH latest_registration AS (
    SELECT DISTINCT ON (dr.drep_hash_id)
        dr.drep_hash_id,
        dr.deposit,
        dr.tx_id AS reg_tx_id,
        b.time AS registration_time,
        b.epoch_no AS registration_epoch
    FROM drep_registration dr
    JOIN tx ON tx.id = dr.tx_id
    JOIN block b ON b.id = tx.block_id
    ORDER BY dr.drep_hash_id, dr.tx_id DESC
),
latest_distribution AS (
    SELECT DISTINCT ON (dd.hash_id)
        dd.hash_id AS drep_hash_id,
        dd.amount AS voting_power,
        dd.epoch_no AS distribution_epoch
    FROM drep_distribution dd
    ORDER BY dd.hash_id, dd.epoch_no DESC
),
vote_delegators AS (
    SELECT
        dv.drep_hash_id,
        COUNT(DISTINCT dv.addr_id) AS delegator_count
    FROM delegation_vote dv
    -- only count latest delegation per stake addr
    WHERE dv.id = (
        SELECT MAX(dv2.id)
        FROM delegation_vote dv2
        WHERE dv2.addr_id = dv.addr_id
    )
    GROUP BY dv.drep_hash_id
),
vote_counts AS (
    SELECT
        vp.drep_voter AS drep_hash_id,
        COUNT(*) AS total_votes,
        COUNT(*) FILTER (WHERE vp.vote = 'Yes') AS yes_votes,
        COUNT(*) FILTER (WHERE vp.vote = 'No') AS no_votes,
        COUNT(*) FILTER (WHERE vp.vote = 'Abstain') AS abstain_votes
    FROM voting_procedure vp
    WHERE vp.drep_voter IS NOT NULL
    GROUP BY vp.drep_voter
)
SELECT
    dh.view AS drep_id,
    dh.raw AS drep_hash,
    dh.has_script AS is_script,
    CASE
        WHEN lr.deposit IS NULL THEN 'never_registered'
        WHEN lr.deposit > 0 THEN 'registered'
        WHEN lr.deposit < 0 THEN 'deregistered'
        ELSE 'updated'
    END AS status,
    lr.registration_time,
    lr.registration_epoch,
    COALESCE(ld.voting_power, 0) AS voting_power,
    ld.distribution_epoch,
    COALESCE(vd.delegator_count, 0) AS delegator_count,
    COALESCE(vc.total_votes, 0) AS total_votes,
    COALESCE(vc.yes_votes, 0) AS yes_votes,
    COALESCE(vc.no_votes, 0) AS no_votes,
    COALESCE(vc.abstain_votes, 0) AS abstain_votes
FROM drep_hash dh
LEFT JOIN latest_registration lr ON lr.drep_hash_id = dh.id
LEFT JOIN latest_distribution ld ON ld.drep_hash_id = dh.id
LEFT JOIN vote_delegators vd ON vd.drep_hash_id = dh.id
LEFT JOIN vote_counts vc ON vc.drep_hash_id = dh.id
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_drep_summary_id
    ON intel_core.drep_summary (drep_id);

CREATE INDEX IF NOT EXISTS idx_drep_summary_power
    ON intel_core.drep_summary (voting_power DESC);

CREATE INDEX IF NOT EXISTS idx_drep_summary_status
    ON intel_core.drep_summary (status);

INSERT INTO intel_meta.view_registry (schema_name, view_name, description, refresh_order)
VALUES ('intel_core', 'drep_summary', 'One row per DRep: voting power, delegators, vote counts', 50)
ON CONFLICT (schema_name, view_name) DO NOTHING;

COMMIT;
