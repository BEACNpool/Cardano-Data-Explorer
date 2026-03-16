-- 013_create_intel_graph_hop_functions.sql
-- SQL functions for multi-hop tracing using both recursive CTEs (shallow) and AGE Cypher (deep).
-- Provides two approaches:
--   1. hop_trace_sql()     — recursive CTE, good for 1-5 hops, no AGE required
--   2. hop_trace_cypher()  — AGE Cypher, good for 5-50+ hops, requires AGE extension
--
-- Rollback: DROP FUNCTION IF EXISTS intel_graph.hop_trace_sql, intel_graph.hop_trace_cypher CASCADE;

BEGIN;

--------------------------------------------------------------------
-- APPROACH 1: Recursive CTE (works without AGE, up to ~5 hops)
--------------------------------------------------------------------
CREATE OR REPLACE FUNCTION intel_graph.hop_trace_sql(
    seed_address TEXT,
    max_hops INTEGER DEFAULT 3,
    min_lovelace BIGINT DEFAULT 0,
    from_epoch INTEGER DEFAULT NULL,
    to_epoch INTEGER DEFAULT NULL
)
RETURNS TABLE (
    hop         INTEGER,
    source_addr TEXT,
    dest_addr   TEXT,
    lovelace    BIGINT,
    tx_hash     TEXT,
    epoch_no    INTEGER,
    tx_time     TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    WITH RECURSIVE trace AS (
        -- Base case: first hop from seed
        SELECT
            1 AS hop,
            ve.source_address,
            ve.dest_address,
            ve.lovelace,
            ve.tx_hash,
            ve.epoch_no::INTEGER,
            ve.tx_time
        FROM intel_graph.value_edges ve
        WHERE ve.source_address = seed_address
          AND ve.lovelace >= min_lovelace
          AND (from_epoch IS NULL OR ve.epoch_no >= from_epoch)
          AND (to_epoch IS NULL OR ve.epoch_no <= to_epoch)

        UNION ALL

        -- Recursive case: follow the chain
        SELECT
            t.hop + 1,
            ve.source_address,
            ve.dest_address,
            ve.lovelace,
            ve.tx_hash,
            ve.epoch_no::INTEGER,
            ve.tx_time
        FROM trace t
        JOIN intel_graph.value_edges ve ON ve.source_address = t.dest_address
        WHERE t.hop < max_hops
          AND ve.lovelace >= min_lovelace
          AND (from_epoch IS NULL OR ve.epoch_no >= from_epoch)
          AND (to_epoch IS NULL OR ve.epoch_no <= to_epoch)
          -- prevent cycles
          AND ve.dest_address != seed_address
    )
    SELECT * FROM trace
    ORDER BY trace.hop, trace.lovelace DESC;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION intel_graph.hop_trace_sql IS
    'Multi-hop forward trace from a seed address using recursive CTE on value_edges. '
    'Good for 1-5 hops. For deeper traces use hop_trace_cypher().';


--------------------------------------------------------------------
-- APPROACH 2: AGE Cypher (requires Apache AGE, handles 5-50+ hops)
--------------------------------------------------------------------

-- This function generates and executes a Cypher query against the AGE graph.
-- It requires that the cardano graph has been populated (see scripts/project_age_graph.sql).
CREATE OR REPLACE FUNCTION intel_graph.hop_trace_cypher(
    seed_address TEXT,
    max_hops INTEGER DEFAULT 10,
    min_ada NUMERIC DEFAULT 0
)
RETURNS TABLE (
    path_json JSONB
) AS $$
DECLARE
    cypher_query TEXT;
BEGIN
    -- Build the Cypher query dynamically
    cypher_query := format(
        'SELECT * FROM cypher(''cardano'', $q$
            MATCH path = (seed:Address {addr: %L})-[:SENT*1..%s]->(dest:Address)
            WHERE ALL(e IN relationships(path) WHERE e.ada >= %s)
            RETURN path
        $q$) AS (path agtype)',
        seed_address,
        max_hops,
        min_ada
    );

    RETURN QUERY EXECUTE cypher_query;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION intel_graph.hop_trace_cypher IS
    'Multi-hop forward trace using Apache AGE Cypher. Handles 5-50+ hops efficiently. '
    'Requires AGE extension and populated cardano graph.';


--------------------------------------------------------------------
-- HELPER: Summarize a hop trace (works with SQL approach)
--------------------------------------------------------------------
CREATE OR REPLACE FUNCTION intel_graph.hop_trace_summary(
    seed_address TEXT,
    max_hops INTEGER DEFAULT 3,
    min_lovelace BIGINT DEFAULT 0
)
RETURNS TABLE (
    hop             INTEGER,
    unique_addrs    BIGINT,
    total_edges     BIGINT,
    total_lovelace  NUMERIC,
    total_ada       NUMERIC,
    min_epoch       INTEGER,
    max_epoch       INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.hop,
        COUNT(DISTINCT t.dest_addr) AS unique_addrs,
        COUNT(*) AS total_edges,
        SUM(t.lovelace)::NUMERIC AS total_lovelace,
        (SUM(t.lovelace) / 1000000.0)::NUMERIC AS total_ada,
        MIN(t.epoch_no) AS min_epoch,
        MAX(t.epoch_no) AS max_epoch
    FROM intel_graph.hop_trace_sql(seed_address, max_hops, min_lovelace) t
    GROUP BY t.hop
    ORDER BY t.hop;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION intel_graph.hop_trace_summary IS
    'Summarized hop trace: per-hop stats (unique addrs, edges, total value, epoch range).';

COMMIT;
