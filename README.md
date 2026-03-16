# Cardano-Data-Explorer

A blueprint and starter kit for building a **comprehensive Cardano data explorer** powered by `cardano-db-sync` and PostgreSQL materialized views.

Look up anything on Cardano: transactions, addresses, stake accounts, pools, delegations, rewards, DReps, governance actions, native assets, and multi-hop value tracing.

## Start here

- Architecture review: [`docs/ARCHITECTURE_REVIEW.md`](docs/ARCHITECTURE_REVIEW.md) — why this design, what alternatives exist, and the recommended build order
- Original blueprint: [`docs/Cardano_Data_Explorer_Blueprint.md`](docs/Cardano_Data_Explorer_Blueprint.md) — detailed infrastructure design
- Quick setup guide: [`docs/QUICKSTART.md`](docs/QUICKSTART.md)
- Environment template: [`templates/.env.example`](templates/.env.example)

## Design in one line

**db-sync indexes the chain. Materialized views make it fast. The explorer makes it accessible.**

## Goals

- Let anyone look up all data on the Cardano blockchain — fast
- Pre-computed intelligence layers (`intel_core`, `intel_graph`, `intel_analytics`) for common queries
- Multi-hop transaction tracing through projected graph edges
- Comprehensive coverage: tx, UTxO, staking, delegation, rewards, governance, native assets
- Fork-friendly: any builder can clone this, point it at their db-sync, and start exploring

## Architecture at a glance

```text
cardano-node → cardano-db-sync → PostgreSQL (primary)
                                       │
                              streaming replication
                              (or query directly)
                                       ▼
                               PostgreSQL (replica)
                              ┌──────────────────┐
                              │ Raw db-sync tables│
                              │ intel_core views  │
                              │ intel_graph views │
                              │ intel_analytics   │
                              └────────┬─────────┘
                                       │
                                   API layer
                                       │
                                  Explorer UI
```

## Current status

This project is in active development. See the architecture review for the recommended build order.

## What this repo is

- A vendor-neutral architecture and implementation blueprint
- A starter structure any builder can fork and adapt
- SQL migrations and materialized view definitions for common Cardano queries
- A foundation for staking, governance, tracing, and analytics workflows

## What this repo is not

- A hosted API service (run your own db-sync)
- A one-click installer (yet)
- A replacement for db-sync — it builds on top of it

## Contributing

PRs are welcome. Please keep changes:

1. Reproducible
2. Environment-agnostic
3. Well-documented with SQL comments
4. Backward-conscious where possible

---
If you want to build your own version, fork this repo and follow `docs/QUICKSTART.md`.
