# Full production database clone → staging

**Primary staging strategy** for TradeTraxs: copy the **entire** production Postgres database (rows, Auth users, RPCs, RLS, relationships) into **`hxlcvffvyadlxcsqxxoy`**. Storage **files** are copied in a separate step.

| | Production `fobudrkniacatvilbofw` | Staging `hxlcvffvyadlxcsqxxoy` |
|--|-----------------------------------|--------------------------------|
| Backup / dump | **Read-only** (`pg_dump` / `supabase db dump`) | — |
| Restore / hardening | **Never** | **Writes only here** |

Official procedure: [Backup and Restore using the CLI](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)

Legacy **schema-only** bootstrap: [`../README.md`](../README.md) (schema_application / forward migrations) — not used for full clone.

## Free-tier staging warning

Supabase **Free** projects have a **500 MB** database limit. If production exceeds this, restore will fail until you **upgrade staging compute/plan** or use a smaller subset (not a full clone).

## Before execution

1. **Production URL (gitignored):** run `./supabase/staging/scripts/full-clone/configure-production-backup-url.sh` and enter the DB password when prompted (hidden). Writes `full-clone/.env.production.local` with URL-encoded password.
2. Copy [`/.env.example`](.env.example) → `.env.local` for staging restore vars when needed.
2. Install **Supabase CLI** (recommended) and/or use **libpq** `pg_dump`/`psql` (already on Mac mini).
3. Complete [`../docs/SIDE_EFFECT_GATES.md`](../docs/SIDE_EFFECT_GATES.md) checklist for hosting **before** turning on staging app traffic (can prep early).
4. Confirm staging disk/plan fits production DB size (Dashboard → Database).

## Execution order (operator)

```bash
chmod +x supabase/staging/scripts/full-clone/*.sh supabase/staging/scripts/lib/*.sh

# 1) Production backup — NO TRADETRAXS_ENV=staging
unset TRADETRAXS_ENV LOADTEST_ENV
export TRADETRAXS_PRODUCTION_DATABASE_URL='postgresql://…db.fobudrkniacatvilbofw…'
./supabase/staging/scripts/full-clone/backup-production-database.sh

# 2) Staging restore — destructive to staging DB
export TRADETRAXS_ENV=staging
export TRADETRAXS_STAGING_DATABASE_URL='postgresql://…db.hxlcvffvyadlxcsqxxoy…'
export TRADETRAXS_FULL_CLONE_CONFIRM=yes
./supabase/staging/scripts/full-clone/restore-staging-database.sh

# 3) Storage bytes (after DB restore)
# Set service role URLs/keys + TRADETRAXS_STORAGE_COPY_CONFIRM=yes
./supabase/staging/scripts/full-clone/copy-storage-objects.sh

# 4) Edge Functions, Auth providers, pgsodium key if using Vault (see Supabase docs)
```

## Rollback (staging only)

Before restore, `restore-staging-database.sh` runs `backup-staging-snapshot.sh` unless `TRADETRAXS_SKIP_STAGING_SNAPSHOT=yes`.

```bash
export TRADETRAXS_ENV=staging
export TRADETRAXS_FULL_CLONE_CONFIRM=yes
pg_restore --clean --if-exists --no-owner --dbname "$TRADETRAXS_STAGING_DATABASE_URL" \
  supabase/staging/artifacts/full-clone/rollback/staging_pre_clone_*.dump
```

Re-verify `\conninfo` shows **`hxlcvffvyadlxcsqxxoy`** before any restore.

## Artifacts (gitignored)

`supabase/staging/artifacts/full-clone/` — `roles.sql`, `schema.sql`, `data.sql`, migration history, rollback `.dump` files.

## Vault / encryption

If production uses **Supabase Vault**, copy the **pgsodium root key** per Supabase docs before relying on copied `vault` ciphertext on staging.

## Troubleshooting restore

See Supabase doc sections: comment `ALTER … OWNER TO supabase_admin` in `schema.sql`, `GRANT postgres TO cli_login_postgres` in `roles.sql`, `session_replication_role = replica` during data load (already in restore script).
