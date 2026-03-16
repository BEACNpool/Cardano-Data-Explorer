# Quickstart

Get from zero to querying Cardano data.

## Prerequisites

- A running `cardano-db-sync` instance with a synced PostgreSQL database
  - [db-sync setup guide](https://github.com/IntersectMBO/cardano-db-sync)
  - Or use a [db-sync snapshot](https://github.com/IntersectMBO/cardano-db-sync/releases) to bootstrap faster
- PostgreSQL 14+ (tuned with [PGTune](https://pgtune.leopard.in.ua/))
- (Optional) [Apache AGE](https://age.apache.org/) for deep hop tracing

## 1) Clone

```bash
git clone https://github.com/BEACNpool/Cardano-Data-Explorer.git
cd Cardano-Data-Explorer
```

## 2) Configure

```bash
cp templates/.env.example .env
```

Edit `.env` with your database connection details. If you're running db-sync locally on the default port, the defaults should work — just set `PGDATABASE` to your db-sync database name (usually `cexplorer`).

## 3) Run migrations

```bash
./scripts/run_migrations.sh
```

This creates all schemas and materialized views (with no data yet).

## 4) Populate views (first run)

```bash
# First run must use --full since views have no existing data
./scripts/refresh_views.sh --full
```

This populates all materialized views. On a full mainnet db-sync database, expect this to take 30–60 minutes for the first run. Subsequent refreshes are faster.

## 5) Start querying

```bash
# Look up an address
psql -c "SELECT * FROM intel_core.address_summary WHERE address = 'addr1q...'"

# Look up a pool
psql -c "SELECT * FROM intel_core.pool_summary WHERE ticker_name = 'BEACN'"

# Look up a DRep
psql -c "SELECT * FROM intel_core.drep_summary WHERE drep_id = 'drep1...'"

# Epoch stats
psql -c "SELECT * FROM intel_core.epoch_summary ORDER BY epoch_no DESC LIMIT 5"

# Multi-hop trace (3 hops from an address)
./scripts/hop_trace.sh DdzFFzCqrh... 3

# Hop trace summary
./scripts/hop_trace.sh --summary DdzFFzCqrh... 5 1000
```

## 6) Set up automatic refresh

Add a cron job to refresh views periodically:

```bash
# Every hour
0 * * * * /path/to/Cardano-Data-Explorer/scripts/refresh_views.sh >> /data/cardano-intel/logs/refresh.log 2>&1
```

Or refresh per schema on different schedules:

```bash
# intel_core every hour (most queried)
0 * * * * /path/to/scripts/refresh_views.sh intel_core
# intel_graph every 6 hours (expensive)
0 */6 * * * /path/to/scripts/refresh_views.sh intel_graph
# intel_analytics daily
0 3 * * * /path/to/scripts/refresh_views.sh intel_analytics
```

## 7) (Optional) Apache AGE for deep hop tracing

If you need 5–50+ hop tracing:

```bash
# Install AGE (see https://age.apache.org/#download)
# Then project the graph:
psql -f sql/intel_graph/project_age_graph.sql
```

Now you can use Cypher queries:

```sql
-- Load AGE
LOAD 'age';
SET search_path = ag_catalog, "$user", public;

-- Find all paths up to 10 hops from an address
SELECT * FROM cypher('cardano', $$
    MATCH path = (seed:Address {addr: 'DdzFFzCqrh...'})-[:SENT*1..10]->(dest)
    RETURN path
$$) AS (path agtype);
```

## What's available after setup

| View | What you can look up |
|---|---|
| `intel_core.address_summary` | Any address: balance, tx count, first/last seen |
| `intel_core.tx_summary` | Any transaction: hash, block, epoch, fee, size |
| `intel_core.tx_io` | Transaction inputs and outputs with resolved addresses |
| `intel_core.stake_summary` | Stake addresses: delegation, rewards, balance |
| `intel_core.pool_summary` | Pools: ticker, stake, delegators, blocks, margin |
| `intel_core.drep_summary` | DReps: voting power, delegators, vote history |
| `intel_core.governance_summary` | Governance proposals: votes, status |
| `intel_core.asset_summary` | Native assets: supply, mints, burns, holders |
| `intel_core.epoch_summary` | Epochs: blocks, txs, fees, staking, treasury |
| `intel_graph.value_edges` | Value flow edges for hop tracing |
| `intel_graph.delegation_edges` | Delegation history edges |
| `intel_graph.reward_edges` | Reward distribution edges |
| `intel_analytics.daily_metrics` | Daily network stats |
| `intel_analytics.pool_epoch_metrics` | Per-pool per-epoch performance |
| `intel_analytics.delegation_concentration` | Nakamoto coefficient over time |
