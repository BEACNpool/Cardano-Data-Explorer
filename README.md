# Cardano-Data-Explorer

Community blueprint for building a **snapshot-based Cardano data warehouse + intelligence explorer** from `cardano-db-sync`.

## Start here

- Core blueprint: [`docs/Cardano_Data_Explorer_Blueprint.md`](docs/Cardano_Data_Explorer_Blueprint.md)
- Quick setup guide: [`docs/QUICKSTART.md`](docs/QUICKSTART.md)
- Environment template: [`templates/.env.example`](templates/.env.example)
- Snapshot metadata template: [`templates/snapshot.meta.example.json`](templates/snapshot.meta.example.json)

## Design in one line

**The sync node syncs. The warehouse stores. The control plane orchestrates. The explorer thinks.**

## Goals

- reproducible snapshot-based analysis
- evidence-first conclusions with provenance
- derived `cardano_intel` layers (core facts, graph, analytics)
- AI-assisted investigation with snapshot awareness

## What this repo is

- A vendor-neutral architecture and implementation blueprint
- A starter structure any operator can fork and adapt
- A foundation for Cardano governance, staking, tracing, and analytics workflows

## What this repo is not

- A real-time explorer deployment
- A one-click installer (yet)
- A canonical source of on-chain truth by itself (db-sync snapshot is the truth input)

## Recommended defaults

- Snapshot cadence: **daily + on-demand**
- Migration style: **plain SQL migrations in-repo**
- Safety: read-only checks can run directly; write/destructive actions should be approved first

## Contributing

PRs are welcome. Please keep changes:

1. Reproducible
2. Evidence/provenance aware
3. Environment-agnostic
4. Backward-conscious where possible

---
If you want to build your own version, fork this repo and follow `docs/QUICKSTART.md`.
