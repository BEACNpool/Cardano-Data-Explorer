-- 012_create_intel_graph_edge_tables.sql
-- Relational edge tables that serve as the source for AGE graph projection.
-- These tables are fast to query with SQL and fast to project into the AGE graph.
--
-- The edge tables are materialized views rebuilt from db-sync raw data.
-- They are the single source of truth for graph topology.
--
-- Rollback: DROP MATERIALIZED VIEW IF EXISTS intel_graph.value_edges,
--           intel_graph.delegation_edges, intel_graph.reward_edges CASCADE;

BEGIN;

--------------------------------------------------------------------
-- VALUE EDGES: one row per value flow (tx_in source → tx_out dest)
--------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS intel_graph.value_edges AS
SELECT
    src_txo.address AS source_address,
    dest_txo.address AS dest_address,
    dest_txo.value AS lovelace,
    encode(spend_tx.hash, 'hex') AS tx_hash,
    spend_tx.id AS tx_id,
    b.epoch_no,
    b.time AS tx_time,
    b.block_no
FROM tx_in ti
-- The transaction that spends (contains this input)
JOIN tx spend_tx ON spend_tx.id = ti.tx_in_id
JOIN block b ON b.id = spend_tx.block_id
-- The source output being consumed
JOIN tx_out src_txo ON src_txo.tx_id = ti.tx_out_id
                   AND src_txo.index = ti.tx_out_index
-- The destination outputs of the spending transaction
JOIN tx_out dest_txo ON dest_txo.tx_id = spend_tx.id
-- Exclude self-sends (change outputs back to same address)
WHERE src_txo.address != dest_txo.address
WITH NO DATA;

-- Indexes for hop tracing queries
CREATE INDEX IF NOT EXISTS idx_value_edges_source
    ON intel_graph.value_edges (source_address);

CREATE INDEX IF NOT EXISTS idx_value_edges_dest
    ON intel_graph.value_edges (dest_address);

CREATE INDEX IF NOT EXISTS idx_value_edges_tx
    ON intel_graph.value_edges (tx_hash);

CREATE INDEX IF NOT EXISTS idx_value_edges_epoch
    ON intel_graph.value_edges (epoch_no);

CREATE INDEX IF NOT EXISTS idx_value_edges_time
    ON intel_graph.value_edges (tx_time);

--------------------------------------------------------------------
-- DELEGATION EDGES: stake_address → pool over time
--------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS intel_graph.delegation_edges AS
SELECT
    sa.view AS stake_address,
    ph.view AS pool_id,
    d.active_epoch_no AS active_epoch,
    b.time AS delegation_time,
    encode(tx.hash, 'hex') AS tx_hash,
    b.epoch_no AS tx_epoch
FROM delegation d
JOIN stake_address sa ON sa.id = d.addr_id
JOIN pool_hash ph ON ph.id = d.pool_hash_id
JOIN tx ON tx.id = d.tx_id
JOIN block b ON b.id = tx.block_id
WITH NO DATA;

CREATE INDEX IF NOT EXISTS idx_delegation_edges_stake
    ON intel_graph.delegation_edges (stake_address);

CREATE INDEX IF NOT EXISTS idx_delegation_edges_pool
    ON intel_graph.delegation_edges (pool_id);

CREATE INDEX IF NOT EXISTS idx_delegation_edges_epoch
    ON intel_graph.delegation_edges (active_epoch);

--------------------------------------------------------------------
-- REWARD EDGES: pool → stake_address per epoch
--------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS intel_graph.reward_edges AS
SELECT
    sa.view AS stake_address,
    ph.view AS pool_id,
    r.type AS reward_type,
    r.amount AS lovelace,
    r.earned_epoch,
    r.spendable_epoch
FROM reward r
JOIN stake_address sa ON sa.id = r.addr_id
LEFT JOIN pool_hash ph ON ph.id = r.pool_id
WITH NO DATA;

CREATE INDEX IF NOT EXISTS idx_reward_edges_stake
    ON intel_graph.reward_edges (stake_address);

CREATE INDEX IF NOT EXISTS idx_reward_edges_pool
    ON intel_graph.reward_edges (pool_id);

CREATE INDEX IF NOT EXISTS idx_reward_edges_epoch
    ON intel_graph.reward_edges (earned_epoch);

-- Register
INSERT INTO intel_meta.view_registry (schema_name, view_name, description, refresh_order) VALUES
    ('intel_graph', 'value_edges', 'Value flow edges: source_addr → dest_addr per tx', 100),
    ('intel_graph', 'delegation_edges', 'Delegation edges: stake_address → pool over time', 101),
    ('intel_graph', 'reward_edges', 'Reward edges: pool → stake_address per epoch', 102)
ON CONFLICT (schema_name, view_name) DO NOTHING;

COMMIT;
