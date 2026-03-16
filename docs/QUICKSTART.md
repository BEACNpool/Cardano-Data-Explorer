# Quickstart (Community Edition)

This guide gets you from zero to a working snapshot-based Cardano data explorer layout.

## 1) Clone

```bash
git clone https://github.com/BEACNpool/Cardano-Data-Explorer.git
cd Cardano-Data-Explorer
```

## 2) Copy templates

```bash
cp templates/.env.example .env
cp templates/snapshot.meta.example.json /tmp/snapshot.meta.json
```

Edit `.env` for your environment.

## 3) Prepare canonical directories (example)

```bash
sudo mkdir -p /data/cardano-intel/{incoming,archive,state,logs,exports}
sudo chown -R "$USER":"$USER" /data/cardano-intel
```

## 4) Snapshot pair rule (mandatory)

Every import must keep these paired:

- `dbsync_epoch_<epoch>_slot_<slot>.dump`
- `dbsync_epoch_<epoch>_slot_<slot>.meta.json`

Never process orphaned files.

## 5) Build order (first practical milestone)

Implement in this order:

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

## 6) Operations doctrine

- Read-only checks: safe to automate
- Write/destructive actions: require explicit approval
- Always attach snapshot provenance to outputs

## 7) Next steps

- Add SQL files under `sql/migrations/`
- Add ETL scripts under `scripts/`
- Add validation checks and tests
- Stand up Superset/Grafana once base layers are ready
