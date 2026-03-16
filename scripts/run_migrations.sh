#!/usr/bin/env bash
# run_migrations.sh — Apply all SQL migrations in order against the target database.
#
# Usage:
#   ./scripts/run_migrations.sh                          # uses .env defaults
#   PGDATABASE=cexplorer ./scripts/run_migrations.sh     # override database
#
# Migrations are idempotent (IF NOT EXISTS / ON CONFLICT DO NOTHING).
# Safe to re-run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MIGRATIONS_DIR="$PROJECT_DIR/sql/migrations"

# Load .env if present
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$PROJECT_DIR/.env"
    set +a
fi

# Database connection defaults (can be overridden via env vars)
export PGHOST="${WAREHOUSE_PGHOST:-${PGHOST:-127.0.0.1}}"
export PGPORT="${WAREHOUSE_PGPORT:-${PGPORT:-5432}}"
export PGUSER="${WAREHOUSE_PGUSER:-${PGUSER:-postgres}}"
export PGDATABASE="${WAREHOUSE_PGDATABASE:-${PGDATABASE:-cexplorer}}"

echo "=== Cardano Data Explorer — Run Migrations ==="
echo "Target: ${PGUSER}@${PGHOST}:${PGPORT}/${PGDATABASE}"
echo ""

# Run each migration file in numeric order
MIGRATION_COUNT=0
FAIL_COUNT=0

for migration in "$MIGRATIONS_DIR"/[0-9]*.sql; do
    [ -f "$migration" ] || continue
    filename="$(basename "$migration")"
    echo -n "  [$filename] ... "

    if psql -v ON_ERROR_STOP=1 -f "$migration" > /dev/null 2>&1; then
        echo "OK"
        MIGRATION_COUNT=$((MIGRATION_COUNT + 1))
    else
        echo "FAILED"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        # Show the error
        psql -v ON_ERROR_STOP=1 -f "$migration" 2>&1 | tail -5
        echo ""
    fi
done

echo ""
echo "=== Done: $MIGRATION_COUNT succeeded, $FAIL_COUNT failed ==="

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
