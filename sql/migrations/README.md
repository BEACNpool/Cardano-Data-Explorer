# SQL Migrations

Numbered SQL files applied in order against a `cardano-db-sync` PostgreSQL database.

## Running migrations

```bash
./scripts/run_migrations.sh
```

Migrations are idempotent (`IF NOT EXISTS`, `ON CONFLICT DO NOTHING`). Safe to re-run.

## Migration order

| # | File | What it does |
|---|---|---|
| 001 | `create_schemas.sql` | Creates `intel_meta`, `intel_core`, `intel_graph`, `intel_labels`, `intel_analytics` schemas |
| 002 | `create_intel_meta.sql` | View registry, refresh log, pipeline config |
| 003 | `create_intel_core_address_summary.sql` | One row per address: balance, tx counts, first/last seen |
| 004 | `create_intel_core_tx_summary.sql` | Enriched tx view + per-tx input/output detail |
| 005 | `create_intel_core_stake_summary.sql` | One row per stake address: delegation, rewards, balance |
| 006 | `create_intel_core_pool_summary.sql` | One row per pool: stake, delegators, blocks, margin |
| 007 | `create_intel_core_drep_summary.sql` | One row per DRep: voting power, delegators, vote counts |
| 008 | `create_intel_core_governance_summary.sql` | One row per governance proposal: votes by role, status |
| 009 | `create_intel_core_asset_summary.sql` | One row per native asset: supply, mints, burns, holders |
| 010 | `create_intel_core_epoch_summary.sql` | One row per epoch: blocks, txs, fees, staking, ada pots |
| 011 | `create_intel_graph_age_setup.sql` | Install Apache AGE extension, create `cardano` graph |
| 012 | `create_intel_graph_edge_tables.sql` | Value, delegation, and reward edge materialized views |
| 013 | `create_intel_graph_hop_functions.sql` | `hop_trace_sql()`, `hop_trace_cypher()`, `hop_trace_summary()` |
| 014 | `create_intel_analytics.sql` | Daily metrics, pool epoch metrics, delegation concentration |
| 015 | `create_intel_labels.sql` | Entity labels, address/stake mappings, evidence tracking |

## After running migrations

1. Refresh all materialized views: `./scripts/refresh_views.sh`
2. (Optional) Project the AGE graph: `psql -f sql/intel_graph/project_age_graph.sql`

## Adding new migrations

- Number sequentially: `016_your_migration.sql`
- Use `IF NOT EXISTS` / `ON CONFLICT DO NOTHING` for idempotency
- Wrap in `BEGIN; ... COMMIT;`
- Include rollback instructions in a comment at the top
