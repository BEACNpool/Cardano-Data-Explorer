#!/usr/bin/env bash
# refresh_views.sh — Refresh all materialized views in dependency order.
#
# Uses REFRESH MATERIALIZED VIEW CONCURRENTLY where possible (requires unique index).
# Logs each refresh to intel_meta.refresh_log.
#
# Usage:
#   ./scripts/refresh_views.sh                   # refresh all enabled views
#   ./scripts/refresh_views.sh intel_core        # refresh only intel_core schema
#   ./scripts/refresh_views.sh --full            # use non-concurrent full refresh
#
# Schedule this via cron or systemd timer:
#   # Every epoch (~5 days) or hourly:
#   0 */1 * * * /path/to/scripts/refresh_views.sh >> /data/cardano-intel/logs/refresh.log 2>&1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load .env if present
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$PROJECT_DIR/.env"
    set +a
fi

export PGHOST="${WAREHOUSE_PGHOST:-${PGHOST:-127.0.0.1}}"
export PGPORT="${WAREHOUSE_PGPORT:-${PGPORT:-5432}}"
export PGUSER="${WAREHOUSE_PGUSER:-${PGUSER:-postgres}}"
export PGDATABASE="${WAREHOUSE_PGDATABASE:-${PGDATABASE:-cexplorer}}"

SCHEMA_FILTER=""
REFRESH_MODE="CONCURRENTLY"

for arg in "$@"; do
    case "$arg" in
        --full)
            REFRESH_MODE=""
            ;;
        *)
            SCHEMA_FILTER="$arg"
            ;;
    esac
done

echo "=== Cardano Data Explorer — Refresh Materialized Views ==="
echo "Target: ${PGUSER}@${PGHOST}:${PGPORT}/${PGDATABASE}"
echo "Mode: ${REFRESH_MODE:-FULL}"
[ -n "$SCHEMA_FILTER" ] && echo "Schema: $SCHEMA_FILTER"
echo "Started: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""

# Get current chain tip for logging
CHAIN_TIP=$(psql -tAc "SELECT block_no || '|' || epoch_no FROM block ORDER BY id DESC LIMIT 1" 2>/dev/null || echo "0|0")
TIP_BLOCK=$(echo "$CHAIN_TIP" | cut -d'|' -f1)
TIP_EPOCH=$(echo "$CHAIN_TIP" | cut -d'|' -f2)
echo "Chain tip: block $TIP_BLOCK, epoch $TIP_EPOCH"
echo ""

# Get views in refresh_order from the registry
FILTER_CLAUSE=""
if [ -n "$SCHEMA_FILTER" ]; then
    FILTER_CLAUSE="AND schema_name = '$SCHEMA_FILTER'"
fi

VIEWS=$(psql -tAc "
    SELECT schema_name || '.' || view_name
    FROM intel_meta.view_registry
    WHERE enabled = TRUE $FILTER_CLAUSE
    ORDER BY refresh_order
" 2>/dev/null || echo "")

if [ -z "$VIEWS" ]; then
    echo "No views found in registry. Run migrations first."
    exit 1
fi

SUCCESS_COUNT=0
FAIL_COUNT=0

while IFS= read -r view; do
    [ -z "$view" ] && continue
    schema_name="${view%%.*}"
    view_name="${view##*.}"

    echo -n "  [$view] ... "

    # Log start
    psql -tAc "
        INSERT INTO intel_meta.refresh_log (schema_name, view_name, db_sync_block, db_sync_epoch)
        VALUES ('$schema_name', '$view_name', $TIP_BLOCK, $TIP_EPOCH)
        RETURNING log_id
    " 2>/dev/null > /tmp/_refresh_log_id || true
    LOG_ID=$(cat /tmp/_refresh_log_id 2>/dev/null | tr -d '[:space:]')

    START_TIME=$(date +%s)

    if psql -v ON_ERROR_STOP=1 -c "REFRESH MATERIALIZED VIEW $REFRESH_MODE $view" > /dev/null 2>&1; then
        ELAPSED=$(( $(date +%s) - START_TIME ))

        # Get row count
        ROW_COUNT=$(psql -tAc "SELECT COUNT(*) FROM $view" 2>/dev/null | tr -d '[:space:]')

        echo "OK (${ELAPSED}s, $ROW_COUNT rows)"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))

        # Log success
        [ -n "$LOG_ID" ] && psql -tAc "
            UPDATE intel_meta.refresh_log
            SET finished_at = now(), status = 'success', row_count = $ROW_COUNT
            WHERE log_id = $LOG_ID
        " > /dev/null 2>&1 || true
    else
        ELAPSED=$(( $(date +%s) - START_TIME ))
        ERROR_MSG=$(psql -v ON_ERROR_STOP=1 -c "REFRESH MATERIALIZED VIEW $REFRESH_MODE $view" 2>&1 | tail -3)
        echo "FAILED (${ELAPSED}s)"
        echo "    $ERROR_MSG"
        FAIL_COUNT=$((FAIL_COUNT + 1))

        # Log failure
        [ -n "$LOG_ID" ] && psql -tAc "
            UPDATE intel_meta.refresh_log
            SET finished_at = now(), status = 'error', error_message = '$(echo "$ERROR_MSG" | head -1 | sed "s/'/''/g")'
            WHERE log_id = $LOG_ID
        " > /dev/null 2>&1 || true
    fi
done <<< "$VIEWS"

echo ""
echo "=== Done: $SUCCESS_COUNT succeeded, $FAIL_COUNT failed ==="
echo "Finished: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
