-- 011_create_intel_graph_age_setup.sql
-- Sets up Apache AGE extension and creates the cardano graph.
-- AGE enables Cypher queries for multi-hop tracing directly inside PostgreSQL.
--
-- Prerequisites: Apache AGE must be installed on the PostgreSQL server.
--   - Packages: https://age.apache.org/#download
--   - Or build from source: https://github.com/apache/age
--
-- Rollback: SELECT drop_graph('cardano', true); DROP EXTENSION IF EXISTS age;

BEGIN;

-- Install the extension
CREATE EXTENSION IF NOT EXISTS age;

-- AGE requires its schema in the search path
-- This should also be set in postgresql.conf: shared_preload_libraries = 'age'
-- and: search_path = '"$user", public, ag_catalog'

-- Create the graph
SELECT create_graph('cardano');

COMMIT;
