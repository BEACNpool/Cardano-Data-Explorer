# Architecture Review: Best Path to a True Cardano Data Explorer

**Date:** 2026-03-16
**Scope:** Evaluate snapshot-based vs. alternative approaches for a general-purpose Cardano Data Explorer

---

## The Goal

Build a **general-purpose Cardano Data Explorer** that lets anyone look up all on-chain data — transactions, UTxOs, delegations, rewards, DReps, pools, governance actions, multi-hop tracing, native assets, and anything else on the Cardano ledger. It should be **fast**, **comprehensive**, and **easy for builders to fork and adapt**.

---

## Honest Assessment of the Snapshot Approach

The current blueprint is built around periodic `pg_dump` snapshots from a `cardano-db-sync` source, restored into a separate analysis database. Here's the honest trade-off:

### What snapshots give you
- Query isolation — heavy analytics can't slow down chain sync
- Reproducibility — fixed point-in-time dataset for each analysis run
- Safety — the sync source is never at risk from bad queries

### What snapshots cost you
- **Data is always stale.** Even with daily snapshots, you're 0–24 hours behind tip. For an "explorer" people expect current data.
- **Double the storage.** Full db-sync mainnet is ~180GB+. You're keeping two copies.
- **Complex pipeline.** Export → transfer → restore → register → rebuild → validate. That's a lot of ceremony before you can query anything.
- **Slow feedback loop.** Want to see the latest epoch's delegation changes? Wait for the next snapshot cycle.
- **Barrier to entry.** Anyone forking this needs to set up snapshot orchestration before they can even start exploring data.

### Verdict on snapshots

Snapshots are the right tool for **forensic investigations** and **reproducible research** — cases where you need a frozen dataset to run heavy analysis against. They are **not** the right primary architecture for a general-purpose data explorer where users expect current, fast lookups.

**Recommendation: Drop snapshots as the primary data path. Keep them as an optional capability for research use cases.**

---

## Recommended Architecture: db-sync + Read Replica + Materialized Views

This is the proven pattern used by most production Cardano data services (Blockfrost, Koios, and others all run db-sync under the hood). Here's how it maps to the project:

### Layer 1: Sync Source (unchanged concept)

```
cardano-node → cardano-db-sync → PostgreSQL (primary)
```

This is your source of truth. db-sync writes to it continuously. **No analytical queries run here.**

### Layer 2: Read Replica (replaces snapshot import)

```
PostgreSQL primary --streaming replication--> PostgreSQL replica (read-only)
```

A standard PostgreSQL streaming replica gives you:
- **Near-real-time data** (seconds of lag, not hours)
- **Full query isolation** from the sync writer
- **Zero import pipeline** — replication is automatic and continuous
- **Same storage footprint** as a snapshot approach, but no manual orchestration

This replica IS your "warehouse" — it replaces the entire snapshot export/import/restore cycle.

For a **single-host deployment** (the likely starting point), you can skip the replica entirely and just query db-sync directly with proper PostgreSQL tuning. Add a replica later when load demands it.

### Layer 3: Intelligence Views (the `cardano_intel` concept, simplified)

Instead of a separate database with ETL pipelines, build **materialized views and summary tables** in a dedicated schema on the same database (or on the replica):

```sql
CREATE SCHEMA intel_core;
CREATE SCHEMA intel_graph;
CREATE SCHEMA intel_labels;
CREATE SCHEMA intel_analytics;
```

These schemas contain pre-computed, indexed materialized views that make common queries fast:

| View | Purpose | Refresh Cadence |
|---|---|---|
| `intel_core.address_summary` | Balance, tx count, first/last seen per address | Every epoch or hourly |
| `intel_core.stake_summary` | Delegation history, rewards, pool association | Every epoch |
| `intel_core.pool_summary` | Saturation, delegator count, blocks minted, margin | Every epoch |
| `intel_core.tx_summary` | Enriched tx view with input/output addresses and values | Continuous or hourly |
| `intel_core.drep_summary` | Voting power, delegator count, votes cast | Every epoch |
| `intel_core.governance_summary` | Proposals, votes, ratification status | Every epoch |
| `intel_core.asset_summary` | Native asset mints, burns, current supply, policy info | Every epoch |
| `intel_graph.value_edges` | Sender→receiver edges for hop tracing | Every epoch |
| `intel_graph.delegation_edges` | Delegator→pool edges over time | Every epoch |
| `intel_analytics.daily_metrics` | Network-wide daily stats | Daily |
| `intel_analytics.epoch_metrics` | Per-epoch aggregate stats | Every epoch |

**Why this is better than the snapshot ETL pipeline:**
- No export/import/restore cycle
- Views refresh in-place with `REFRESH MATERIALIZED VIEW CONCURRENTLY`
- Queries keep working during refresh (no downtime)
- Single database to back up, tune, and manage
- New builders can fork, point at their db-sync, create the views, and go

### Layer 4: API + Frontend

A REST/GraphQL API reads from the materialized views for fast responses, falling back to the raw db-sync tables for detailed queries. This is the layer that serves the actual explorer UI.

---

## Architecture Diagram

```text
┌─────────────────────────────┐
│ cardano-node                │
│ cardano-db-sync             │
│ PostgreSQL (primary writer) │
│                             │
│ NO analytical queries here  │
└─────────────┬───────────────┘
              │
              │ streaming replication (automatic, near-real-time)
              │ (or: query directly on single-host setups)
              ▼
┌─────────────────────────────────────────────┐
│ PostgreSQL (read replica / query target)     │
│                                             │
│ ┌─────────────────────────────────────────┐ │
│ │ Raw db-sync tables (public schema)      │ │
│ │ — block, tx, tx_out, tx_in, etc.        │ │
│ │ — full chain history, always current    │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ ┌─────────────────────────────────────────┐ │
│ │ intel_core (materialized views)         │ │
│ │ — address_summary, pool_summary, etc.   │ │
│ │ — refreshed every epoch / hourly        │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ ┌─────────────────────────────────────────┐ │
│ │ intel_graph (materialized views)        │ │
│ │ — value_edges, delegation_edges         │ │
│ │ — enables multi-hop tracing             │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ ┌─────────────────────────────────────────┐ │
│ │ intel_analytics (materialized views)    │ │
│ │ — daily_metrics, epoch_metrics          │ │
│ └─────────────────────────────────────────┘ │
└─────────────────┬───────────────────────────┘
                  │
                  │ SQL queries
                  ▼
┌─────────────────────────────┐
│ API Layer (REST / GraphQL)  │
│ — fast reads from mat views │
│ — detailed queries from raw │
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────┐
│ Explorer Frontend           │
│ — tx lookup, address pages  │
│ — pool/delegation views     │
│ — DRep/governance views     │
│ — hop tracing UI            │
│ — charts and analytics      │
└─────────────────────────────┘
```

---

## What About the Alternatives to db-sync?

The Cardano indexing landscape has evolved significantly. Here's where things stand:

### db-sync — still the right default for a comprehensive explorer

Despite its resource requirements (64GB RAM, high-IOPS SSD recommended), db-sync remains the **most complete** Cardano indexer. It captures everything: transactions, UTxOs, staking, rewards, governance, native assets, scripts, metadata, pool registrations — all in a well-normalized PostgreSQL schema.

For a project whose goal is "look up ALL data on Cardano," db-sync's completeness is a feature, not a bug.

### Alternatives worth knowing about

| Tool | When to consider it | Why NOT for this project |
|---|---|---|
| **Carp** (dcSpark) | You only need specific data subsets | Requires defining custom execution plans; for "all data" you'd index everything anyway |
| **Oura** (TxPipe) | Event-driven pipelines, webhooks | Pipeline tool, not a queryable database |
| **Scrolls** (TxPipe) | Fast key-value lookups, distributed cache | No relational queries, no joins, no complex analytics |
| **Blockfrost API** | Quick prototyping, no infra management | Third-party dependency; rate-limited; can't customize |
| **Koios API** | Free community API, no infra | Same — external dependency, can't extend |
| **Ledger Sync** (Cardano Foundation) | Enterprise/Java shops, parallel sync | Newer, less community tooling, Java ecosystem |
| **Acropolis** (IOG, Rust) | Future — lower resource data node | Still in development (2025-2026 roadmap) |

**Bottom line:** If you want to provide ALL Cardano data and allow builders to extend it, db-sync + PostgreSQL is still the most practical foundation. The alternatives are better for scoped use cases.

### Future-proofing

The project should be designed so the **intelligence layer (materialized views, schemas) is independent of the indexer**. If Acropolis or Ledger Sync matures and provides the same PostgreSQL schema, switching the data source should be a config change, not a rewrite.

---

## Comparison: Snapshot vs. Read Replica vs. Direct Query

| Aspect | Snapshot (current) | Read Replica (recommended) | Direct Query |
|---|---|---|---|
| Data freshness | Hours behind | Seconds behind | Real-time |
| Query isolation | Full | Full | None (risky) |
| Setup complexity | High (export/import pipeline) | Medium (pg streaming replication) | Low |
| Storage overhead | 2x (source + warehouse) | 2x (primary + replica) | 1x |
| Maintenance | Manual orchestration | Automatic replication | None |
| Time to first query | Hours (after snapshot cycle) | Minutes (after replica catches up) | Immediate |
| Best for | Forensic research | Production explorer | Dev/testing |
| Single-host viable | Yes but complex | Yes (can defer replica) | Yes |

---

## Recommended Build Order

### Phase 1 — Foundation (get data queryable)
1. Document db-sync setup requirements and PostgreSQL tuning
2. Write SQL migrations for `intel_core` schema with key materialized views
3. `intel_core.address_summary` — the most common explorer query
4. `intel_core.tx_summary` — enriched transaction view with inputs/outputs
5. `intel_core.stake_summary` — delegation and reward tracking
6. `intel_core.pool_summary` — pool stats and delegation info

### Phase 2 — Breadth (cover all major data types)
7. `intel_core.drep_summary` — governance delegation
8. `intel_core.governance_summary` — proposals and voting
9. `intel_core.asset_summary` — native assets and policies
10. `intel_core.epoch_summary` — per-epoch network stats
11. Refresh orchestration script (cron or systemd timer to refresh mat views)

### Phase 3 — Depth (hop tracing and graph)
12. `intel_graph.value_edges` — tx input/output edges for hop tracing
13. `intel_graph.delegation_edges` — delegation relationship edges
14. Multi-hop trace query functions (recursive CTEs on edge tables)
15. `intel_labels.entities` — known entity labels (exchanges, pools, foundation, etc.)

### Phase 4 — API
16. REST API for common lookups (address, tx, pool, stake key, DRep)
17. Hop-tracing API endpoint
18. Search endpoint (address, tx hash, pool ticker, asset name)

### Phase 5 — Frontend
19. Explorer UI — address pages, tx pages, pool pages
20. Governance dashboard
21. Graph/hop visualization
22. Network analytics charts

### Optional: Research Mode (snapshot capability)
- For users who want point-in-time analysis, provide a `snapshot_mode.md` runbook
- This uses the existing snapshot blueprint as an optional add-on, not the primary path

---

## Single-Host Quick Start (simplest path)

For someone who just wants to get started on one machine:

1. Run `cardano-node` + `cardano-db-sync` + PostgreSQL (tuned with PGTune)
2. Use IOHK/Intersect db-sync snapshots for fast initial sync
3. Create the `intel_core` schema and materialized views
4. Query directly — no replica needed at this scale
5. Set up a cron job to refresh materialized views every epoch (~5 days) or hourly
6. Add a read replica later when query load justifies it

This gets a builder from zero to "I can look up anything on Cardano" in the shortest time possible.

---

## Sources

- [cardano-db-sync best practices (Cardano Docs)](https://docs.cardano.org/cardano-components/cardano-db-sync/best-practices/)
- [cardano-db-sync GitHub](https://github.com/IntersectMBO/cardano-db-sync)
- [Carp vs alternatives (dcSpark)](https://dcspark.github.io/carp/docs/comparison/)
- [Carp indexer announcement (Medium)](https://medium.com/dcspark/carp-new-cardano-sql-indexer-replacement-for-db-sync-b990243a329e)
- [Scrolls — read-optimized cache (GitHub)](https://github.com/txpipe/scrolls)
- [Ledger Sync (Cardano Foundation)](https://cardanofoundation.org/blog/accessing-cardano-blockchain-data-with-ledger-sync)
- [Blockfrost RYO (GitHub)](https://github.com/blockfrost/blockfrost-backend-ryo)
- [Koios API](https://api.koios.rest)
- [Acropolis / IOG Q3 2025 report](https://iohk.io/en/blog/posts/2025/10/29/strengthening-cardanos-foundations-q3-2025-progress-report/)
- [PostgreSQL materialized views best practices](https://medium.com/@ShivIyer/optimizing-materialized-views-in-postgresql-best-practices-for-performance-and-efficiency-3e8169c00dc1)
- [Blockfrost.io](https://blockfrost.io/)
