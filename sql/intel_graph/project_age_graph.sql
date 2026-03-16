-- project_age_graph.sql
-- Projects the relational value_edges into the Apache AGE graph for Cypher queries.
-- Run this after refreshing intel_graph.value_edges.
--
-- This script:
--   1. Clears the existing graph data
--   2. Creates Address nodes for all unique addresses in value_edges
--   3. Creates SENT edges between addresses with tx metadata
--
-- WARNING: This is a full rebuild. For large datasets, consider incremental projection.
-- On mainnet with hundreds of millions of edges, this may take significant time.
-- Consider projecting only the subgraph you need (e.g., specific epoch ranges).
--
-- Prerequisites: Apache AGE installed, 'cardano' graph created (migration 011)
-- Usage: psql -f sql/intel_graph/project_age_graph.sql

-- Ensure AGE is loaded
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

--------------------------------------------------------------------
-- Step 1: Clear existing graph data
--------------------------------------------------------------------

-- Drop all edges
SELECT * FROM cypher('cardano', $$
    MATCH ()-[e]->()
    DELETE e
$$) AS (result agtype);

-- Drop all nodes
SELECT * FROM cypher('cardano', $$
    MATCH (n)
    DELETE n
$$) AS (result agtype);

--------------------------------------------------------------------
-- Step 2: Create Address nodes from unique addresses
--------------------------------------------------------------------

-- Create nodes for all source addresses
SELECT * FROM cypher('cardano', $$
    UNWIND $addresses AS addr
    MERGE (a:Address {addr: addr})
$$, (SELECT jsonb_agg(DISTINCT source_address) AS addresses FROM intel_graph.value_edges)
) AS (result agtype);

-- Create nodes for all destination addresses not already created
SELECT * FROM cypher('cardano', $$
    UNWIND $addresses AS addr
    MERGE (a:Address {addr: addr})
$$, (SELECT jsonb_agg(DISTINCT dest_address) AS addresses FROM intel_graph.value_edges)
) AS (result agtype);

--------------------------------------------------------------------
-- Step 3: Create SENT edges with metadata
--------------------------------------------------------------------
-- NOTE: For mainnet, you will want to batch this by epoch range.
-- This example projects all edges. Adjust the WHERE clause to scope it.

-- We use a helper temp table to batch the inserts
CREATE TEMP TABLE IF NOT EXISTS _edge_batch AS
SELECT
    source_address,
    dest_address,
    lovelace,
    lovelace / 1000000.0 AS ada,
    tx_hash,
    epoch_no,
    block_no
FROM intel_graph.value_edges;

-- Project edges in batches by epoch (adjust range as needed)
DO $$
DECLARE
    epoch_rec RECORD;
    batch_size INTEGER := 10000;
BEGIN
    FOR epoch_rec IN
        SELECT DISTINCT epoch_no FROM _edge_batch ORDER BY epoch_no
    LOOP
        -- For each epoch, create edges
        EXECUTE format(
            'SELECT * FROM cypher(''cardano'', $q$
                UNWIND $edges AS e
                MATCH (src:Address {addr: e.src}), (dst:Address {addr: e.dst})
                CREATE (src)-[:SENT {
                    lovelace: e.lovelace,
                    ada: e.ada,
                    tx_hash: e.tx_hash,
                    epoch: e.epoch,
                    block: e.block
                }]->(dst)
            $q$, (
                SELECT jsonb_agg(jsonb_build_object(
                    ''src'', source_address,
                    ''dst'', dest_address,
                    ''lovelace'', lovelace,
                    ''ada'', ada,
                    ''tx_hash'', tx_hash,
                    ''epoch'', epoch_no,
                    ''block'', block_no
                ))
                FROM _edge_batch
                WHERE epoch_no = %s
            )) AS (result agtype)',
            epoch_rec.epoch_no
        );

        RAISE NOTICE 'Projected epoch %', epoch_rec.epoch_no;
    END LOOP;
END;
$$;

DROP TABLE IF EXISTS _edge_batch;

-- Verify
SELECT * FROM cypher('cardano', $$
    MATCH (n:Address)
    RETURN count(n) AS node_count
$$) AS (node_count agtype);

SELECT * FROM cypher('cardano', $$
    MATCH ()-[e:SENT]->()
    RETURN count(e) AS edge_count
$$) AS (edge_count agtype);
