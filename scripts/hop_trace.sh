#!/usr/bin/env bash
# hop_trace.sh — Quick multi-hop trace from the command line.
#
# Usage:
#   ./scripts/hop_trace.sh <address> [max_hops] [min_ada]
#
# Examples:
#   ./scripts/hop_trace.sh DdzFFzCqrh...  3           # 3 hops, no min
#   ./scripts/hop_trace.sh DdzFFzCqrh...  5 1000      # 5 hops, min 1000 ADA
#   ./scripts/hop_trace.sh addr1q...      10           # Shelley address, 10 hops
#
# For summary view (per-hop stats):
#   ./scripts/hop_trace.sh --summary DdzFFzCqrh... 5

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

export PGHOST="${WAREHOUSE_PGHOST:-${PGHOST:-127.0.0.1}}"
export PGPORT="${WAREHOUSE_PGPORT:-${PGPORT:-5432}}"
export PGUSER="${WAREHOUSE_PGUSER:-${PGUSER:-postgres}}"
export PGDATABASE="${WAREHOUSE_PGDATABASE:-${PGDATABASE:-cexplorer}}"

SUMMARY=false
if [ "${1:-}" = "--summary" ]; then
    SUMMARY=true
    shift
fi

ADDRESS="${1:?Usage: hop_trace.sh [--summary] <address> [max_hops] [min_ada]}"
MAX_HOPS="${2:-3}"
MIN_ADA="${3:-0}"
MIN_LOVELACE=$((MIN_ADA * 1000000))

echo "=== Hop Trace ==="
echo "Seed: $ADDRESS"
echo "Max hops: $MAX_HOPS"
echo "Min ADA: $MIN_ADA"
echo ""

if [ "$SUMMARY" = true ]; then
    psql -c "
        SELECT * FROM intel_graph.hop_trace_summary(
            '$ADDRESS',
            $MAX_HOPS,
            $MIN_LOVELACE
        );
    "
else
    psql -c "
        SELECT
            hop,
            LEFT(source_addr, 20) || '...' AS source,
            LEFT(dest_addr, 20) || '...' AS dest,
            lovelace / 1000000.0 AS ada,
            LEFT(tx_hash, 16) || '...' AS tx,
            epoch_no,
            tx_time::DATE AS date
        FROM intel_graph.hop_trace_sql(
            '$ADDRESS',
            $MAX_HOPS,
            $MIN_LOVELACE
        )
        ORDER BY hop, lovelace DESC
        LIMIT 500;
    "
fi
