# Cardano Data Explorer

**Version:** Public Community Edition v1  
**Date:** 2026-03-16  
**Status:** Community blueprint for building a snapshot-based Cardano explorer and analytics stack  
**Primary audience:** builders, operators, researchers, contributors

---

# 1. Mission

**Cardano Data Explorer** is a blueprint for turning a raw `cardano-db-sync` dataset into a **forensic-grade Cardano analysis and explorer system** capable of:

- historical chain analysis
- staking and delegation intelligence
- multi-hop value tracing
- pool and entity profiling
- governance and DRep analysis
- graph-based relationship analysis
- evidence-first labeling and casework
- AI-assisted investigation and summarization

Cardano Data Explorer is **not** designed primarily as a tip-of-chain explorer.

Its purpose is **depth, reproducibility, transparency, and analytical power**.

---

# 2. Core Doctrine

## 2.1 Snapshot-first, not live-query

Cardano Data Explorer runs on **periodic PostgreSQL snapshots** exported from a `cardano-db-sync` PostgreSQL database and imported into an isolated analysis environment.

This is a deliberate design choice.

### Why this model exists

- The sync node’s job is to **sync the chain**.
- The analysis environment’s job is to **think**.
- Heavy analytical queries should not compete with chain sync duties.
- Reproducible investigations require a **fixed point-in-time dataset**.
- Derived layers should rebuild against a stable base, not a moving target.

### Operating slogan

**The sync node syncs. The warehouse stores. The control plane orchestrates. Cardano Data Explorer thinks.**

---

## 2.2 One-way data flow

All core ledger data should flow in one direction:

**sync source → warehouse / analysis stack**

There should be **no write-back** from the analytics platform to the sync source.

---

## 2.3 Evidence-first standard

Every meaningful conclusion produced by Cardano Data Explorer should be traceable to:

- a specific imported snapshot
- specific chain-derived records
- known transformation logic
- known label or evidence provenance
- a known tool or analyst workflow

If a claim cannot be tied back to evidence and snapshot provenance, it is not yet production-grade output.

---

# 3. Reference Topology

This project works best when split into three logical roles.

## 3.1 Sync Source

**Role:** chain sync and raw db-sync source

**Responsibilities:**
- run `cardano-node`
- run `cardano-db-sync`
- host the source PostgreSQL database used for snapshot export
- perform snapshot dump generation

**Constraints:**
- no heavy analytical querying
- no graph rebuilds
- no dashboard workloads
- no AI workloads

---

## 3.2 Warehouse Host

**Role:** permanent explorer and intelligence warehouse host

**Responsibilities:**
- host the main PostgreSQL workloads
- store imported raw snapshots
- store derived analytics data
- maintain state, logs, and archive control data
- act as the durable backbone for the platform

---

## 3.3 Control Plane / Ops Box

**Role:** orchestration, operator workspace, agent control plane

**Responsibilities:**
- run automation or agent tooling
- hold runbooks, docs, and scripts
- coordinate snapshot and ETL workflows
- perform read-only checks directly where allowed
- propose-first for write or destructive operations
- serve as the main human and bot operations console

This machine is the **brain / operator station**, not necessarily the permanent warehouse host.

---

# 4. Bot / Agent Policy

## 4.1 Allowed without prior proposal

Automation may directly execute **read-only checks**, including:

- host reachability checks
- `df -h`
- `ls`, `find`, `du`
- process inspection (`pgrep`, `ps`, etc.)
- service status inspection
- read-only SQL queries
- snapshot metadata inspection
- log inspection
- checksum verification
- restore progress checks that do not alter state

## 4.2 Must propose first

Automation should **propose first** before any write or destructive action, including:

- creating or dropping databases
- running `pg_restore`
- moving, renaming, or deleting snapshot files
- truncating or rebuilding derived tables
- editing configs
- changing services
- creating migrations
- altering schemas
- refreshing expensive materialized views
- killing processes
- changing permissions or ownership
- modifying systemd or cron jobs
- changing active snapshot markers

### Simple rule

When in doubt:
- read-only = allowed
- write/destructive = propose first

---

# 5. Topology Diagram

```text
┌──────────────────────────────┐
│ Sync Source                  │
│                              │
│ cardano-node                 │
│ cardano-db-sync              │
│ PostgreSQL (source of truth) │
│                              │
│ Export snapshots only        │
└──────────────┬───────────────┘
               │
               │ pg_dump / transfer
               ▼
┌──────────────────────────────┐
│ Warehouse Host               │
│                              │
│ raw snapshot database        │
│ derived intelligence DB      │
│ active snapshot state        │
│ graph / analytics / search   │
└──────────────┬───────────────┘
               ▲
               │ orchestrates / inspects / manages
               │
┌──────────────────────────────┐
│ Control Plane / Ops Box      │
│                              │
│ agents / automation          │
│ runbooks                     │
│ scripts                      │
│ operator workspace           │
└──────────────────────────────┘
```

---

# 6. Database Model

## 6.1 Core logical split

Cardano Data Explorer should operate with two logical layers:

### `cardano_raw`
Purpose:
- imported point-in-time `db-sync` snapshot
- canonical raw warehouse for a specific snapshot
- full replacement on each import

### `cardano_intel`
Purpose:
- all derived intelligence layers
- labels, graph projections, analytics, search, AI notes, casework, provenance metadata

## 6.2 Important principle

`cardano_raw` is **replaced per snapshot**.

`cardano_intel` is **rebuilt against that fixed snapshot** using either:
- delta rebuild when safe
- full rebuild when required

---

# 7. Snapshot Ingestion Model

## 7.1 Snapshot lifecycle

### Step 1 — Export snapshot from the sync source
Naming standard:

```text
dbsync_epoch_{epoch}_slot_{slot}.dump
```

A matching metadata file should travel with the dump.

Suggested pair:

```text
dbsync_epoch_{epoch}_slot_{slot}.dump
dbsync_epoch_{epoch}_slot_{slot}.meta.json
```

### Step 2 — Transfer to warehouse host
The `.dump` and `.meta.json` should always remain paired.

### Step 3 — Restore into `cardano_raw`
`cardano_raw` is treated as a clean imported warehouse copy.

This is a **replacement import**, not a merge.

### Step 4 — Register snapshot provenance
Metadata should be written into provenance tables and the active snapshot marker system.

### Step 5 — Rebuild derived layers
The ETL pipeline reads from `cardano_raw` and writes to `cardano_intel`.

Pipeline order must be deterministic.

### Step 6 — Validate
Validation should confirm:
- imported tip matches expected snapshot metadata
- rebuild completed cleanly
- key counts are sane
- no orphan graph references
- known test addresses, pools, or DReps check out

---

# 8. Snapshot Cadence

## 8.1 Default recommendation

A strong default is:
- **daily** snapshots
- plus **on-demand** snapshots for major events, incidents, investigations, or governance needs

## 8.2 Important expectation

Cardano Data Explorer is **not** a real-time system.

Freshness is chosen based on investigative need, not explorer-style latency expectations.

---

# 9. Canonical Filesystem Pattern

This blueprint intentionally avoids environment-specific paths. A simple recommended pattern is:

```text
/data/cardano-intel/
├─ incoming/
├─ archive/
├─ state/
├─ logs/
└─ exports/
```

Suggested meanings:

- `incoming/` — newly transferred snapshots waiting for import
- `archive/` — older retained dumps and metadata
- `state/` — active snapshot marker, pipeline state, checkpoint files
- `logs/` — import and ETL logs
- `exports/` — optional local exports and generated bundles

### Active snapshot marker

Suggested path:

```text
/data/cardano-intel/state/active_snapshot.json
```

This file should summarize at minimum:
- active snapshot tag
- snapshot id if known
- epoch
- slot
- block
- block hash
- import time
- processed time
- rebuild mode
- validation status

---

# 10. Provenance and Metadata Requirements

## 10.1 Snapshot provenance is mandatory

Every major derived process should tie back to snapshot provenance.

The warehouse should maintain an `intel_meta` schema with at least:

- `snapshot_registry`
- `refresh_log`
- `pipeline_checkpoints`
- heuristic or schema version metadata

## 10.2 `snapshot_registry`

Suggested fields:
- `snapshot_id`
- `snapshot_tag`
- `epoch_no`
- `slot_no`
- `block_no`
- `block_time`
- `block_hash`
- `dump_file`
- `dump_size_bytes`
- `source_host`
- `imported_at`
- `processed_at`
- `previous_snapshot_id`
- `delta_blocks`
- `rebuild_mode`
- `status`
- `error_message`
- `notes`

---

# 11. ETL Model

## 11.1 Trigger model

ETL is **snapshot-triggered**, not continuously running against live block arrival.

That means:
- import snapshot
- register provenance
- run ordered ETL pipeline
- validate
- update active snapshot state

## 11.2 ETL job families

### Job Family A — Core facts
Examples:
- address summaries
- stake account summaries
- pool summaries
- delegation timelines
- reward timelines
- asset and policy summaries
- governance summaries

### Job Family B — Graph projections
Examples:
- graph nodes
- value edges
- delegation edges
- reward edges
- governance edges
- optional path and reachability helpers

### Job Family C — Analytics
Examples:
- daily metrics
- concentration tables
- pool trend tables
- DRep concentration
- anomaly flags

### Job Family D — Search layer
Examples:
- lookup catalogs
- search documents
- fuzzy search prep

### Job Family E — AI / retrieval support
Examples:
- retrieval chunks for chain-derived profiles
- cached summaries
- evidence references
- snapshot-aware AI context tables

---

# 12. Intelligence Layer Design

## 12.1 `intel_core`
Purpose:
- business-ready and investigator-ready facts

Suggested objects:
- `address_summary`
- `stake_account_summary`
- `pool_summary`
- `delegation_timeline`
- `reward_timeline`
- `asset_summary`
- `policy_summary`
- `governance_action_summary`
- `drep_summary`

## 12.2 `intel_graph`
Purpose:
- support hop tracing and relationship analysis

Suggested objects:
- `graph_nodes`
- `graph_edges_value`
- `graph_edges_delegation`
- `graph_edges_reward`
- `graph_edges_governance`
- optional `trace_seed_sets`
- optional `reachable_sets`

## 12.3 `intel_labels`
Purpose:
- entity abstraction and evidence-backed labeling

Suggested objects:
- `entities`
- `entity_addresses`
- `entity_stake_keys`
- `entity_pools`
- `labels`
- `evidence_registry`

## 12.4 `intel_analytics`
Purpose:
- precomputed metrics and trend views

Suggested objects:
- `daily_network_metrics`
- `daily_pool_metrics`
- `daily_entity_flow_metrics`
- `delegation_concentration_metrics`
- `drep_concentration_metrics`
- `anomaly_flags`

## 12.5 `intel_ai`
Purpose:
- AI memory and agent support

Suggested objects:
- `investigation_notes`
- `claim_registry`
- `claim_evidence_links`
- `agent_runs`
- `retrieval_chunks`

---

# 13. Graph and Tracing Strategy

## 13.1 Start with graph projection in PostgreSQL

Recommended first implementation:
- use projected edge tables in PostgreSQL
- use recursive CTEs only against projected graph tables, not raw UTxO joins
- optionally use Python or NetworkX for analyst-only heavy graph logic

Why this is a strong starting point:
- simpler than maintaining a dedicated graph database immediately
- stays close to the truth store
- easier backup and restore
- easier AI integration because one database remains central

## 13.2 Types of graph queries to support

- immediate value tracing
- multi-hop tracing
- clustering and recurring counterparty discovery
- governance coordination views
- temporal graphing between date windows

---

# 14. Visualization Stack

## 14.1 Internal dashboards

Recommended:
- **Apache Superset** for exploratory analytics
- **Grafana** for operational metrics and time-series dashboards

## 14.2 Public or premium frontend

Recommended:
- React or Next.js frontend
- ECharts for charts
- Cytoscape.js for graph exploration

## 14.3 Research notebooks

Recommended:
- JupyterLab
- Polars or Pandas
- Plotly
- NetworkX

---

# 15. AI / Agent Integration Strategy

## 15.1 Good use cases

AI should help with:
- natural-language query translation into safe tasks
- investigation summaries
- comparative analysis
- draft write-ups and case notes
- label suggestion and cluster hypothesis generation
- anomaly explanation

## 15.2 Guardrails

AI should not:
- freely generate arbitrary expensive SQL against raw db-sync
- create unsupported claims without evidence linkage
- assign labels without confidence and provenance
- act as the final arbiter of attribution

## 15.3 Snapshot awareness

Any AI-generated answer about chain state should know which snapshot it is referencing.

That means AI outputs should ideally include:
- snapshot tag
- snapshot block or epoch context
- supporting evidence or SQL result references

---

# 16. Migrations and Change Management

## 16.1 Recommended default

A strong default for community deployment is:

- **plain SQL migrations in-repo**

Why:
- simple
- transparent
- easy to audit
- easy to reproduce
- minimal moving parts

Suggested repo pattern:

```text
sql/
├─ migrations/
├─ intel_core/
├─ intel_graph/
├─ intel_meta/
└─ intel_analytics/
```

## 16.2 Delta safety rules

Automatically fall back to a **full rebuild** when:
- schema version changed
- previous snapshot is missing
- previous snapshot is not a strict ancestor
- block hash continuity check fails
- a critical derived table failed previously
- heuristic logic changed materially

---

# 17. Suggested Repo Structure

```text
lantern-cardano/
├─ README.md
├─ docs/
│  ├─ Cardano Data Explorer_Blueprint.md
│  ├─ snapshot_runbook.md
│  ├─ restore_runbook.md
│  ├─ etl_runbook.md
│  ├─ validation_runbook.md
│  └─ investigations/
├─ sql/
│  ├─ migrations/
│  ├─ intel_core/
│  ├─ intel_graph/
│  ├─ intel_meta/
│  └─ intel_analytics/
├─ python/
│  ├─ etl/
│  ├─ analytics/
│  ├─ graph/
│  ├─ ai/
│  └─ utils/
├─ apps/
│  ├─ api/
│  ├─ web/
│  └─ notebooks/
├─ infra/
└─ tests/
```

---

# 18. Credibility Standard

The platform should aim for this standard:

> every meaningful conclusion can be traced back to the chain data, transformation logic, and supporting evidence used to produce it

That means every major output should preserve:
- exact source rows or references
- transformation lineage
- label provenance
- confidence score
- timestamp or time-window context
- analyst or agent attribution

This is what separates a serious Cardano intelligence system from an ordinary dashboard.

---

# 19. Final Framing

Cardano Data Explorer is not just a “better explorer.”

It is a blueprint for a **Cardano intelligence operating system** with:
- canonical raw warehouse snapshots
- derived intelligence facts
- graph relationships
- search and retrieval
- premium charting
- AI-assisted investigation
- saved casework
- evidence-first transparency

That architecture gives builders room to support:
- staking research
- delegation and pool oversight
- DRep and governance analysis
- treasury transparency
- founder-era tracing
- entity mapping
- anomaly monitoring
- public intelligence products

---

# 20. Immediate Build Order

Build the first production-grade version of these in order:

1. `intel_meta.snapshot_registry`
2. `intel_meta.refresh_log`
3. `intel_meta.pipeline_checkpoints`
4. `intel_core.address_summary`
5. `intel_core.stake_account_summary`
6. `intel_core.pool_summary`
7. `intel_labels.entities`
8. `intel_labels.evidence_registry`
9. `intel_graph.graph_nodes`
10. `intel_graph.graph_edges_value`
11. `intel_analytics.daily_pool_metrics`
12. internal Superset dashboards

Once those exist, the system stops being just an idea and starts becoming a real Cardano explorer and intelligence engine.
