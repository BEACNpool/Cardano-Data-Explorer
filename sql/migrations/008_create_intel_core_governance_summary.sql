-- 008_create_intel_core_governance_summary.sql
-- Materialized view: one row per governance action proposal with vote tallies.
--
-- Depends on: public.gov_action_proposal, public.voting_procedure, public.voting_anchor,
--             public.tx, public.block
-- Rollback: DROP MATERIALIZED VIEW IF EXISTS intel_core.governance_summary CASCADE;

BEGIN;

CREATE MATERIALIZED VIEW IF NOT EXISTS intel_core.governance_summary AS
WITH vote_tallies AS (
    SELECT
        vp.gov_action_proposal_id,
        vp.voter_role,
        COUNT(*) AS total_votes,
        COUNT(*) FILTER (WHERE vp.vote = 'Yes') AS yes_votes,
        COUNT(*) FILTER (WHERE vp.vote = 'No') AS no_votes,
        COUNT(*) FILTER (WHERE vp.vote = 'Abstain') AS abstain_votes
    FROM voting_procedure vp
    GROUP BY vp.gov_action_proposal_id, vp.voter_role
),
drep_votes AS (
    SELECT gov_action_proposal_id, total_votes, yes_votes, no_votes, abstain_votes
    FROM vote_tallies WHERE voter_role = 'DRep'
),
spo_votes AS (
    SELECT gov_action_proposal_id, total_votes, yes_votes, no_votes, abstain_votes
    FROM vote_tallies WHERE voter_role = 'SPO'
),
cc_votes AS (
    SELECT gov_action_proposal_id, total_votes, yes_votes, no_votes, abstain_votes
    FROM vote_tallies WHERE voter_role = 'ConstitutionalCommittee'
)
SELECT
    gap.id AS proposal_id,
    encode(tx.hash, 'hex') AS proposal_tx_hash,
    gap.index AS proposal_index,
    gap.type AS action_type,
    gap.description,
    gap.deposit AS proposal_deposit,
    sa.view AS return_address,
    b.epoch_no AS proposed_epoch,
    b.time AS proposed_time,
    gap.expiration AS expiration_epoch,
    gap.ratified_epoch,
    gap.enacted_epoch,
    gap.dropped_epoch,
    gap.expired_epoch,
    CASE
        WHEN gap.enacted_epoch IS NOT NULL THEN 'enacted'
        WHEN gap.ratified_epoch IS NOT NULL THEN 'ratified'
        WHEN gap.dropped_epoch IS NOT NULL THEN 'dropped'
        WHEN gap.expired_epoch IS NOT NULL THEN 'expired'
        ELSE 'active'
    END AS status,
    -- DRep votes
    COALESCE(dv.total_votes, 0) AS drep_total_votes,
    COALESCE(dv.yes_votes, 0) AS drep_yes,
    COALESCE(dv.no_votes, 0) AS drep_no,
    COALESCE(dv.abstain_votes, 0) AS drep_abstain,
    -- SPO votes
    COALESCE(sv.total_votes, 0) AS spo_total_votes,
    COALESCE(sv.yes_votes, 0) AS spo_yes,
    COALESCE(sv.no_votes, 0) AS spo_no,
    COALESCE(sv.abstain_votes, 0) AS spo_abstain,
    -- CC votes
    COALESCE(cv.total_votes, 0) AS cc_total_votes,
    COALESCE(cv.yes_votes, 0) AS cc_yes,
    COALESCE(cv.no_votes, 0) AS cc_no,
    COALESCE(cv.abstain_votes, 0) AS cc_abstain
FROM gov_action_proposal gap
JOIN tx ON tx.id = gap.tx_id
JOIN block b ON b.id = tx.block_id
LEFT JOIN stake_address sa ON sa.id = gap.return_address
LEFT JOIN drep_votes dv ON dv.gov_action_proposal_id = gap.id
LEFT JOIN spo_votes sv ON sv.gov_action_proposal_id = gap.id
LEFT JOIN cc_votes cv ON cv.gov_action_proposal_id = gap.id
WITH NO DATA;

CREATE UNIQUE INDEX IF NOT EXISTS idx_gov_summary_id
    ON intel_core.governance_summary (proposal_id);

CREATE INDEX IF NOT EXISTS idx_gov_summary_type
    ON intel_core.governance_summary (action_type);

CREATE INDEX IF NOT EXISTS idx_gov_summary_status
    ON intel_core.governance_summary (status);

CREATE INDEX IF NOT EXISTS idx_gov_summary_epoch
    ON intel_core.governance_summary (proposed_epoch DESC);

INSERT INTO intel_meta.view_registry (schema_name, view_name, description, refresh_order)
VALUES ('intel_core', 'governance_summary', 'One row per governance proposal: votes by DRep/SPO/CC, status', 60)
ON CONFLICT (schema_name, view_name) DO NOTHING;

COMMIT;
