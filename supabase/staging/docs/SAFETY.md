# Staging bootstrap safety model

## Fail-closed controls (tooling)

| Control | Mechanism |
|---------|-----------|
| Live DB identity | `psql \conninfo` host + `postgres.<ref>` user must match expected ref |
| Staging writes | `tradetraxs_assert_staging_live_database` on restore, verify, forward apply, repair (optional URL), seed |
| Production export | Live ref must equal allowlisted production ref; rejects `TRADETRAXS_ENV=staging` during export |
| Read-only export | `PGOPTIONS=-c default_transaction_read_only=on`; fails if role has `CREATE` unless override |
| Artifact scan | Rejects `COPY`, `INSERT`, Auth identity inserts, customer table inserts, vault secrets; application dump must include `handle_new_user`; platform dump must include signup trigger + storage policies |
| Managed schemas | Export dumps `auth`/`storage` only into a filtered `schema_platform_custom.sql` (no base `CREATE TABLE`/`CREATE SCHEMA` on fresh Supabase); restore applies **application → platform → buckets** with `ON_ERROR_STOP` |
| Verification gate | `artifacts/.staging_schema_verified.json` — not forgeable via env var |
| Migration repair | Requires stamp; `forward_verified` when manifest has apply lines |
| Reference seed | `002` not auto-run; `seed-staging-reference.sh` blocks placeholders and active writes |
| CLI linkage | `mark-baseline-migrations-applied.sh` aborts if CLI linked to production ref file |
| No `supabase link` | Repair uses `--project-ref` only; does not modify link files |

## Manual verification still required

- Review export artifacts for sensitive **comments** or hardcoded URLs (automated scan is not exhaustive).
- Confirm export role is read-only in Supabase Dashboard (not just `CREATE` privilege probe).
- Pooler URLs: prefer direct `db.<ref>.supabase.co` for identity checks.
- Do not apply raw full-schema dumps for `auth`/`storage`/`realtime` on a fresh Supabase project — use the split artifacts from `export-production-schema.sh`.
- Auth **configuration** (providers, JWT, SMTP) is never in schema dumps — configure staging separately.
- `storage.objects` is excluded from dump; bucket **rows** come from `001_storage_buckets.sql`.

## Hardcoded production identifiers (intentional blocklist)

- `TRADETRAXS_PRODUCTION_PROJECT_REF` default `fobudrkniacatvilbofw` in `project-guard.sh` (deny target for staging)
- `TRADETRAXS_ALLOWED_STAGING_PROJECT_REF` `hxlcvffvyadlxcsqxxoy` — only ref permitted for restore / forward / verify / load tests
- Production hostnames in load-test and guard scripts
- Documentation references only — not used for staging connections

Production **credentials** must never be committed. Export uses operator-supplied `TRADETRAXS_PRODUCTION_DATABASE_URL` only.
