# Scripts

Operational scripts for managing the Cardano Data Explorer.

## Available scripts

| Script | Purpose |
|---|---|
| `run_migrations.sh` | Apply all SQL migrations in order |
| `refresh_views.sh` | Refresh all materialized views (with logging) |
| `hop_trace.sh` | Quick multi-hop trace from the command line |

## run_migrations.sh

Applies all numbered SQL files from `sql/migrations/` against the target database.

```bash
./scripts/run_migrations.sh
```

## refresh_views.sh

Refreshes materialized views in dependency order. Uses `REFRESH CONCURRENTLY` by default.

```bash
./scripts/refresh_views.sh                   # all views
./scripts/refresh_views.sh intel_core        # only intel_core views
./scripts/refresh_views.sh --full            # non-concurrent full refresh (first run)
```

**First run:** Use `--full` since concurrent refresh requires existing data.

**Schedule:** Add to cron for automatic refresh:
```bash
# Refresh every hour
0 * * * * /path/to/scripts/refresh_views.sh >> /data/cardano-intel/logs/refresh.log 2>&1
```

## hop_trace.sh

Quick command-line multi-hop tracing from a seed address.

```bash
./scripts/hop_trace.sh <address> [max_hops] [min_ada]
./scripts/hop_trace.sh --summary <address> [max_hops] [min_ada]
```

Examples:
```bash
./scripts/hop_trace.sh DdzFFzCqrh... 3              # 3 hops from Byron address
./scripts/hop_trace.sh addr1q... 5 1000              # 5 hops, only flows >= 1000 ADA
./scripts/hop_trace.sh --summary DdzFFzCqrh... 5     # per-hop aggregate stats
```

## Environment

All scripts read from `.env` in the project root if present. Override with env vars:

```bash
PGHOST=192.168.1.100 PGDATABASE=cexplorer ./scripts/refresh_views.sh
```
