# SQL Migrations

Use plain SQL, numbered in execution order.

Example:

- `001_create_intel_meta.sql`
- `002_create_snapshot_registry.sql`
- `003_create_refresh_log.sql`

Guidelines:
- deterministic
- idempotent where practical
- include rollback notes in comments
- never hide breaking changes
