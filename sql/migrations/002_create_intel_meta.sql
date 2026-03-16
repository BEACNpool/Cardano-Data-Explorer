-- 002_create_intel_meta.sql
-- Infrastructure tables for tracking materialized view refreshes and pipeline state.
--
-- Rollback: DROP TABLE intel_meta.view_registry, intel_meta.refresh_log, intel_meta.pipeline_config CASCADE;

BEGIN;

-- Tracks every materialized view managed by the explorer
CREATE TABLE IF NOT EXISTS intel_meta.view_registry (
    view_id         SERIAL PRIMARY KEY,
    schema_name     TEXT NOT NULL,
    view_name       TEXT NOT NULL,
    description     TEXT,
    refresh_order   INTEGER NOT NULL DEFAULT 0,
    depends_on      TEXT[],              -- array of schema.view names this depends on
    avg_refresh_sec NUMERIC,
    enabled         BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (schema_name, view_name)
);

-- Log of every refresh attempt
CREATE TABLE IF NOT EXISTS intel_meta.refresh_log (
    log_id          BIGSERIAL PRIMARY KEY,
    schema_name     TEXT NOT NULL,
    view_name       TEXT NOT NULL,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at     TIMESTAMPTZ,
    status          TEXT NOT NULL DEFAULT 'running',  -- running, success, error
    row_count       BIGINT,
    error_message   TEXT,
    db_sync_block   BIGINT,                           -- block_no at time of refresh
    db_sync_epoch   INTEGER                           -- epoch_no at time of refresh
);

CREATE INDEX IF NOT EXISTS idx_refresh_log_view
    ON intel_meta.refresh_log (schema_name, view_name, started_at DESC);

-- Key-value config for pipeline behavior
CREATE TABLE IF NOT EXISTS intel_meta.pipeline_config (
    key             TEXT PRIMARY KEY,
    value           TEXT NOT NULL,
    description     TEXT,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Seed default config
INSERT INTO intel_meta.pipeline_config (key, value, description) VALUES
    ('refresh_mode', 'concurrent', 'concurrent or full — concurrent keeps views queryable during refresh'),
    ('default_cadence', 'epoch', 'epoch or hourly — how often to refresh views'),
    ('age_graph_name', 'cardano', 'Name of the Apache AGE graph')
ON CONFLICT (key) DO NOTHING;

COMMIT;
