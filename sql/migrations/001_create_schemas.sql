-- 001_create_schemas.sql
-- Creates the core intelligence schemas used by Cardano Data Explorer.
-- These schemas sit alongside the public schema populated by cardano-db-sync.
--
-- Rollback: DROP SCHEMA intel_meta, intel_core, intel_graph, intel_labels, intel_analytics CASCADE;

BEGIN;

CREATE SCHEMA IF NOT EXISTS intel_meta;
CREATE SCHEMA IF NOT EXISTS intel_core;
CREATE SCHEMA IF NOT EXISTS intel_graph;
CREATE SCHEMA IF NOT EXISTS intel_labels;
CREATE SCHEMA IF NOT EXISTS intel_analytics;

COMMENT ON SCHEMA intel_meta IS 'Pipeline metadata: refresh logs, view registry, config';
COMMENT ON SCHEMA intel_core IS 'Pre-computed materialized views for fast explorer lookups';
COMMENT ON SCHEMA intel_graph IS 'Apache AGE graph projection and edge tables for hop tracing';
COMMENT ON SCHEMA intel_labels IS 'Entity labels and evidence-backed attributions';
COMMENT ON SCHEMA intel_analytics IS 'Aggregate metrics and trend data';

COMMIT;
