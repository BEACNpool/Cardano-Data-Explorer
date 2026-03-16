# Project Review: Cardano Data Explorer

**Date:** 2026-03-16
**Reviewer:** Claude (automated review)
**Scope:** Full project assessment — architecture, priorities, and alignment with genesis ADA tracking mission

---

## Executive Summary

This repo is currently **documentation-only**. It contains a well-thought-out architectural blueprint for a snapshot-based Cardano data warehouse, but **zero working code** — no SQL migrations, no scripts, no ETL logic, no Python modules. The blueprint itself is solid infrastructure design, but it is **too generic and too broad** for what actually matters most: **tracking what happened to the ~31.1 billion genesis ADA**.

**Verdict: Keep the architecture. Radically narrow the priorities. Start building real code immediately.**

The project does not need to change direction — it needs to **pick a direction and execute on it**. Right now it's an ambitious architecture document that tries to serve every possible Cardano analytics use case equally. For the genesis ADA mission, it needs to become a focused forensic tool first, and a general-purpose platform second.

---

## What Exists Today

| Component | Status |
|---|---|
| Architecture blueprint | Complete, thorough |
| Quickstart guide | Exists but no code to quickstart with |
| SQL migrations | Empty directory with a README placeholder |
| Scripts | Empty directory with a README placeholder |
| Python ETL/analytics | Does not exist (not even a directory) |
| Templates | `.env.example` and `snapshot.meta.example.json` only |
| Tests | Does not exist |
| Any working query | None |

**Bottom line:** The repo is 100% planning, 0% implementation.

---

## What's Right (Keep These)

1. **Snapshot-first doctrine** — Correct. Running forensic queries against a live sync node is a bad idea. Periodic snapshot import into an isolated analysis DB is the right call.

2. **Two-database split (`cardano_raw` / `cardano_intel`)** — Sound design. Raw imported data stays pristine; derived intelligence layers rebuild against it.

3. **Evidence-first standard** — Essential for the genesis ADA mission. Every claim about where ADA went must trace back to specific transactions and blocks.

4. **Graph projection in PostgreSQL** — Good starting point. Multi-hop value tracing through recursive CTEs on projected edge tables is exactly what genesis tracing needs.

5. **Provenance tracking** — Knowing which snapshot produced which conclusions is critical for reproducibility.

6. **Bot/agent safety policy** — Read-only checks are safe; destructive actions require approval. Good operational discipline.

---

## What's Wrong (Must Change)

### 1. No Implementation Exists

The most critical problem. Three commits in, and the repo has produced zero executable artifacts. The build order in Section 20 of the blueprint lists 12 items to build — none of them exist. Not a single CREATE TABLE statement, not a single SQL query, not a single Python script.

**Fix:** Start writing real SQL and real code immediately. One working migration file is worth more than another page of architecture docs.

### 2. Genesis ADA Tracking Is Buried

The stated mission — tracking what happened to the genesis ADA — appears exactly once in the entire blueprint, as a single bullet point:

> "founder-era tracing"

That's it. The rest of the blueprint treats governance analysis, DRep concentration, daily pool metrics, and AI investigation notes as equal priorities. They're not. If tracking genesis ADA is the mission, the entire build order needs to reflect that.

**Fix:** Reorder priorities so genesis ADA tracing drives the first deliverables.

### 3. Build Order Doesn't Serve the Mission

The current build order (Section 20) starts with:
1. `snapshot_registry`
2. `refresh_log`
3. `pipeline_checkpoints`
4. `address_summary`
5. `stake_account_summary`
6. `pool_summary`

Items 1-3 are infrastructure — fine. But items 4-6 are generic summaries that don't directly help trace genesis ADA. `pool_summary` has nothing to do with finding where 31 billion ADA went. The build order should go directly from infrastructure into genesis-specific tables.

### 4. No Genesis-Specific Data Model

The blueprint has no schema or design for:
- Identifying the genesis UTxO set from `cardano-db-sync`
- Classifying genesis addresses (AVVM public sale vs. nonAvvmBalances organizational allocations)
- Tracking first-spend transactions from genesis outputs
- Multi-hop forward tracing from genesis addresses
- Entity clustering of genesis-connected address groups
- Era-crossing tracking (Byron addresses → Shelley migration → current state)

This is the core of what the project needs, and it's completely absent.

### 5. Too Many Aspirational Components

The blueprint describes AI investigation notes, retrieval chunks, claim registries, Superset dashboards, React frontends, Cytoscape.js graph visualization, JupyterLab notebooks, Grafana metrics, and more. These are all fine goals for a mature platform, but listing them now — before a single table exists — creates the illusion of progress and dilutes focus.

**Fix:** Strip the build order down to what directly serves genesis ADA tracking. Everything else is Phase 2+.

---

## The Genesis ADA Problem: What Needs to Be Built

### Background

At Cardano's launch (September 29, 2017), the Byron-era genesis block distributed approximately **31,112,484,646 ADA** across two categories:

1. **AVVM distribution (`avvmDistr`):** ~25.9B ADA to public sale participants who bought ADA vouchers between September 2015 and January 2017. These were issued as Byron-era redeem addresses.

2. **Non-AVVM balances (`nonAvvmBalances`):** ~5.2B ADA to three organizational entities:
   - **IOHK** (Input Output Hong Kong) — development
   - **EMURGO** — commercial adoption
   - **Cardano Foundation** — ~648M ADA for ecosystem stewardship

### What "Track Down Genesis ADA" Actually Means

To trace all genesis ADA, you need to answer these questions:

1. **Which addresses received genesis ADA?** — Extract all genesis UTxOs from block 0 in `cardano-db-sync`.
2. **When did each genesis address first spend?** — Find the first transaction consuming each genesis UTxO.
3. **Where did it go?** — For each first-spend, identify the output addresses and amounts.
4. **Where did it go after that?** — Multi-hop forward tracing from genesis outputs through the full transaction graph.
5. **Who controls the destination addresses?** — Entity clustering: group addresses that appear as co-inputs in the same transaction (common-input-ownership heuristic).
6. **How much genesis ADA is still unspent at original genesis addresses?** — Some AVVM addresses may never have been redeemed.
7. **How did genesis ADA cross eras?** — Byron bootstrap addresses → Shelley base addresses. Many holders migrated wallets; need to link old and new addresses.
8. **Where is it now?** — Current UTxO holders, staking delegations, and exchange deposits traceable back to genesis.

### Proposed Genesis-Focused Build Order

**Phase 0 — Infrastructure (keep from current blueprint)**
1. `intel_meta.snapshot_registry` — snapshot provenance
2. `intel_meta.refresh_log` — pipeline run tracking
3. `intel_meta.pipeline_checkpoints` — idempotent rebuild support

**Phase 1 — Genesis Foundation**
4. `intel_genesis.genesis_utxos` — all UTxOs from block 0 with classification (AVVM vs. organizational)
5. `intel_genesis.genesis_addresses` — all addresses that received genesis ADA, with labels where known
6. `intel_genesis.genesis_first_spend` — first transaction consuming each genesis UTxO (when, where, how much)
7. `intel_genesis.genesis_address_current_balance` — current balance of original genesis addresses (unredeemed AVVM detection)

**Phase 2 — Forward Tracing**
8. `intel_graph.graph_nodes` — address/stake-key/tx nodes
9. `intel_graph.graph_edges_value` — value flow edges from tx_out/tx_in joins
10. `intel_genesis.genesis_flow_hops` — multi-hop forward trace from genesis UTxOs (configurable depth)
11. `intel_genesis.genesis_era_migration` — Byron → Shelley address migration linkage

**Phase 3 — Entity Intelligence**
12. `intel_labels.entities` — entity clusters (co-input heuristic + known labels)
13. `intel_labels.entity_addresses` — address-to-entity mapping
14. `intel_labels.evidence_registry` — why we believe an address belongs to an entity
15. `intel_genesis.genesis_entity_summary` — how much genesis ADA each entity cluster controls

**Phase 4 — Analytics & Reporting**
16. `intel_analytics.genesis_flow_summary` — aggregate: how much ADA flowed where, by era, by entity type
17. `intel_analytics.genesis_concentration` — current concentration of genesis ADA across entities
18. `intel_core.address_summary` — general address summaries (now useful because graph exists)
19. `intel_core.stake_account_summary` — staking analysis layered on top

**Phase 5 — Visualization & AI (only after data exists)**
20. Superset dashboards on genesis flow data
21. Notebook-based investigation workflows
22. AI-assisted summarization of genesis entity profiles

---

## Key SQL Starting Points

These queries against a `cardano-db-sync` database would be the first real implementation:

### Query 1: Extract all genesis UTxOs
```sql
-- All transaction outputs from block 0 (genesis block)
SELECT
    tx.hash AS tx_hash,
    txo.index AS output_index,
    txo.address,
    txo.value AS lovelace,
    txo.value / 1000000.0 AS ada
FROM tx_out txo
JOIN tx ON tx.id = txo.tx_id
JOIN block b ON b.id = tx.block_id
WHERE b.block_no = 0
ORDER BY txo.value DESC;
```

### Query 2: Which genesis UTxOs have been spent?
```sql
-- Genesis UTxOs and their spend status
SELECT
    txo.address,
    txo.value / 1000000.0 AS genesis_ada,
    CASE WHEN txi.id IS NOT NULL THEN 'SPENT' ELSE 'UNSPENT' END AS status,
    spend_tx.hash AS spent_in_tx,
    spend_block.time AS spent_at,
    spend_block.epoch_no AS spent_epoch
FROM tx_out txo
JOIN tx ON tx.id = txo.tx_id
JOIN block b ON b.id = tx.block_id
LEFT JOIN tx_in txi ON txi.tx_out_id = txo.tx_id AND txi.tx_out_index = txo.index
LEFT JOIN tx spend_tx ON spend_tx.id = txi.tx_in_id
LEFT JOIN block spend_block ON spend_block.id = spend_tx.block_id
WHERE b.block_no = 0
ORDER BY txo.value DESC;
```

### Query 3: First-hop destinations of spent genesis ADA
```sql
-- Where genesis ADA went on first spend
WITH genesis_spends AS (
    SELECT
        txo.address AS genesis_address,
        txo.value AS genesis_lovelace,
        txi.tx_in_id AS spend_tx_id
    FROM tx_out txo
    JOIN tx ON tx.id = txo.tx_id
    JOIN block b ON b.id = tx.block_id
    JOIN tx_in txi ON txi.tx_out_id = txo.tx_id AND txi.tx_out_index = txo.index
    WHERE b.block_no = 0
)
SELECT
    gs.genesis_address,
    gs.genesis_lovelace / 1000000.0 AS genesis_ada,
    dest_out.address AS destination_address,
    dest_out.value / 1000000.0 AS destination_ada,
    dest_block.time AS tx_time,
    dest_block.epoch_no AS epoch
FROM genesis_spends gs
JOIN tx_out dest_out ON dest_out.tx_id = gs.spend_tx_id
JOIN tx dest_tx ON dest_tx.id = gs.spend_tx_id
JOIN block dest_block ON dest_block.id = dest_tx.block_id
ORDER BY gs.genesis_lovelace DESC, dest_out.value DESC;
```

---

## Recommended Repo Structure Changes

### Current structure (documentation-only):
```
cardano-data-explorer/
├─ docs/           # blueprint + quickstart
├─ scripts/        # empty README
├─ sql/migrations/ # empty README
└─ templates/      # .env + snapshot meta examples
```

### Proposed structure (implementation-ready):
```
cardano-data-explorer/
├─ docs/
│  ├─ Cardano_Data_Explorer_Blueprint.md
│  ├─ QUICKSTART.md
│  └─ PROJECT_REVIEW.md          # this document
├─ sql/
│  ├─ migrations/
│  │  ├─ 001_create_intel_meta_schema.sql
│  │  ├─ 002_create_snapshot_registry.sql
│  │  ├─ 003_create_refresh_log.sql
│  │  ├─ 004_create_pipeline_checkpoints.sql
│  │  ├─ 005_create_intel_genesis_schema.sql
│  │  ├─ 006_create_genesis_utxos.sql
│  │  ├─ 007_create_genesis_addresses.sql
│  │  ├─ 008_create_genesis_first_spend.sql
│  │  └─ ...
│  ├─ intel_genesis/              # genesis-specific queries and views
│  ├─ intel_core/
│  ├─ intel_graph/
│  ├─ intel_meta/
│  └─ intel_analytics/
├─ scripts/
│  ├─ import_snapshot.sh
│  ├─ run_pipeline.sh
│  ├─ populate_genesis_utxos.sh
│  └─ validate_snapshot.sh
├─ python/
│  ├─ genesis/                    # genesis ADA tracing logic
│  ├─ etl/
│  ├─ graph/
│  └─ utils/
├─ templates/
├─ tests/
└─ README.md
```

---

## Specific File-Level Recommendations

### README.md
- Rewrite to lead with the genesis ADA tracking mission
- Remove vague "community blueprint" framing — state the concrete goal
- Add a "Current Status" section showing what's implemented

### docs/Cardano_Data_Explorer_Blueprint.md
- Section 20 (Build Order): Replace with the genesis-focused build order above
- Section 12 (Intelligence Layer): Add `intel_genesis` schema alongside existing schemas
- Section 13 (Graph/Tracing): Add specific genesis forward-tracing strategy
- Section 1 (Mission): Put "genesis ADA forensic tracing" as the first bullet, not buried

### sql/migrations/
- Start writing actual SQL files immediately
- Begin with the `intel_meta` infrastructure tables, then go straight to `intel_genesis`

### scripts/
- Write `populate_genesis_utxos.sh` as the first real script — it runs the genesis extraction query against `cardano_raw` and populates `intel_genesis.genesis_utxos`

---

## Risk Assessment

| Risk | Severity | Mitigation |
|---|---|---|
| Continued planning without implementation | **Critical** | Start writing SQL now. One migration file per day minimum. |
| Scope creep into generic analytics | High | Keep genesis tracking as Phase 1. Everything else is Phase 2+. |
| No access to a synced `cardano-db-sync` instance | High | Need at least one synced db-sync PostgreSQL database to test against. This is a hard prerequisite. |
| Multi-hop tracing is computationally expensive | Medium | Use projected graph edge tables, not raw UTxO joins. Limit hop depth. Materialize results. |
| Byron → Shelley address migration is complex | Medium | Use known migration patterns. Co-input heuristic helps link old and new addresses. |
| AVVM redemption addresses are non-standard | Low | Well-documented in cardano-node Byron genesis format. db-sync handles the conversion. |

---

## Final Recommendation

**Stay the course on architecture. Radically change the execution priority.**

The blueprint's infrastructure design (snapshot-first, two-database split, evidence provenance, graph projection) is sound and directly serves the genesis ADA mission. Don't throw it away.

But the project needs three immediate changes:

1. **Narrow the focus.** Genesis ADA tracking is the mission. Everything else (DRep analysis, daily pool metrics, AI notes) is Phase 2+. Remove them from the immediate build order.

2. **Start building.** Write the first SQL migration files. Write the first genesis extraction queries. Get them tested against a real `cardano-db-sync` database. The architecture is done — the implementation is overdue.

3. **Add `intel_genesis` as a first-class schema.** The current blueprint has `intel_core`, `intel_graph`, `intel_labels`, `intel_analytics`, and `intel_ai`. It needs `intel_genesis` — a dedicated schema for genesis block analysis, forward tracing, and era-crossing address linkage. This is the schema that directly answers "what happened to all the genesis ADA."

---

## Sources

- [Cardano Genesis Distribution (cardano.org)](https://cardano.org/genesis/)
- [cardano-db-sync interesting queries](https://github.com/input-output-hk/cardano-db-sync/blob/master/doc/interesting-queries.md)
- [Byron genesis data format](https://cardanoupdates.com/docs/46a81f56-741b-40f7-843a-11e75f5550c9)
- [cardano-sl genesis configuration (Serokell)](https://github.com/serokell/cardano-sl/blob/master/docs/configuration.md)
- [cardano-db-sync UTxO set issue #254](https://github.com/input-output-hk/cardano-db-sync/issues/254)
- [Cardano Developer Portal — Addresses](https://developers.cardano.org/docs/learn/core-concepts/addresses/)
