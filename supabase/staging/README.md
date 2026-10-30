# TradeTraxs staging

Staging project ref (allowlist): **`hxlcvffvyadlxcsqxxoy`** · Production (never write): **`fobudrkniacatvilbofw`**

## Primary: full production database clone

Copy **all** production database rows (Auth users, trades, messages, profiles, RPCs, RLS) into staging.

**Runbook:** [`full-clone/README.md`](full-clone/README.md)  
**Side effects:** [`docs/SIDE_EFFECT_GATES.md`](docs/SIDE_EFFECT_GATES.md)  
**Deep reference:** [`docs/FULL_PRODUCTION_CLONE.md`](docs/FULL_PRODUCTION_CLONE.md)

Scripts (do not run until configured):

| Script | Target |
|--------|--------|
| `scripts/full-clone/backup-production-database.sh` | Production read-only |
| `scripts/full-clone/backup-staging-snapshot.sh` | Staging rollback snapshot |
| `scripts/full-clone/restore-staging-database.sh` | Staging only |
| `scripts/full-clone/copy-storage-objects.sh` | Prod read / staging write (manual bulk step) |

Artifacts: `artifacts/full-clone/` (gitignored).

---

## Legacy: schema-only bootstrap

For sanitized baselines without customer data (CI / empty staging):

- `scripts/export-production-schema.sh` → `schema_application.sql` + `schema_platform_custom.sql`
- `scripts/restore-staging-schema.sh`, `forward_migrations.manifest`, `run-verify.sh`

See historical steps in git history; not the default when doing a **full clone**.

---

## Layout

```
supabase/staging/
  full-clone/           # env example + README (primary)
  artifacts/            # gitignored dumps
  scripts/full-clone/   # backup / restore / verify
  scripts/              # legacy schema-only + guards
  verify/
  docs/
```

Guards live in `scripts/lib/project-guard.sh` (project ref allowlist + live `\conninfo` checks).
