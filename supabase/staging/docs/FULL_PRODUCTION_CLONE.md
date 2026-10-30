# Full production clone → staging (TradeTraxs)

**Status:** Plan only — do not run until operator sign-off.  
**Source (read-only ops):** `fobudrkniacatvilbofw`  
**Destination (writes only here):** `hxlcvffvyadlxcsqxxoy`

This replaces the **schema-only** bootstrap (`schema_application.sql` / `schema_platform_custom.sql`) when the goal is a **full environment copy** (rows, Auth users, Storage objects, preserved UUIDs).

Official references:

- [Migrating within Supabase](https://supabase.com/docs/guides/platform/migrating-within-supabase)
- [Backup and Restore using the CLI](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)
- [Restore dashboard backup](https://supabase.com/docs/guides/platform/migrating-within-supabase/dashboard-restore)
- [Restore to a new project (clone)](https://supabase.com/docs/guides/platform/clone-project)
- [Database backups](https://supabase.com/docs/guides/platform/backups)

---

## 1. Decision: native clone vs restore into existing staging

| Approach | Fits `hxlcvffvyadlxcsqxxoy`? | Database + Auth users | Storage files | Effort |
|----------|------------------------------|------------------------|---------------|--------|
| **A. Restore to a New Project** (Dashboard) | **No** — Supabase creates a **new** project ref | Yes (physical backup) | **No** | Lowest for DB+Auth only |
| **B. CLI / logical backup → restore** | **Yes** | Yes (with correct dump flags) | Separate step | Medium; matches your existing staging ref |
| **C. Dashboard `.backup` → restore to staging** | **Yes** (via restore connection) | Yes | **No** | Medium |

**Recommendation for TradeTraxs (keep existing staging ref, full data):**

Use **B (CLI backup-restore)** or **C (dashboard backup file)** to load **into `hxlcvffvyadlxcsqxxoy`**, then run a **Storage object copy** pass, then redeploy Edge Functions and reconfigure Auth/API secrets on staging only.

Use **A (Clone)** only if you accept a **new** project ref and later point “staging” env vars at that ref (leave `hxlcvffvyadlxcsqxxoy` unused). Clone is **not** a in-place upgrade of an empty staging project.

### Clone feature — cost and limits ([docs](https://supabase.com/docs/guides/platform/clone-project))

- **Requires:** Paid plan + **physical backups** enabled on source (Postgres 15.8.1.079+ on platform).
- **Billing:** New project billed like a second production mirror (compute tier, disk, egress). Dashboard shows **estimated monthly cost before you confirm**.
- **Included in clone:** Schema, data, indexes, roles, **Auth user rows** (hashed passwords).
- **Not included:** Storage objects, Edge Functions, Auth provider settings, API keys, Realtime config, extension *settings*.
- **Restrictions:** Clone target **cannot** be used as a source for another clone (beta). **PITR** optional add-on (~$100+/mo tier depending on retention — see [PITR pricing](https://supabase.com/docs/guides/platform/backups#pricing)).

---

## 2. Pre-migration audit (both projects)

Run from a secure machine. **Production:** read-only queries or Dashboard only until backup starts.

### Source `fobudrkniacatvilbofw`

- [ ] Plan tier, Postgres version (17.6), physical backups enabled?
- [ ] Database size (Dashboard → Database → overview) and largest tables (`trades`, `messages`, Storage metadata).
- [ ] Extensions enabled (`pg_graphql`, `pg_cron`, `pg_net`, `vault`, etc.) — note any that call **external** URLs.
- [ ] `supabase_migrations.schema_migrations` row count (migration history).
- [ ] Auth: user count, OAuth providers, MFA, email templates.
- [ ] Storage: bucket list (see `bootstrap/001_storage_buckets.sql` + verification SQL — 12 buckets).
- [ ] Edge Functions deployed (repo: `supabase/functions/guest-session`).
- [ ] Secrets: Vault / `broker_integration_connections` / Stripe customer IDs in DB — treat as **live production credentials** after copy.
- [ ] Network: IP restrictions, SSL mode.

### Destination `hxlcvffvyadlxcsqxxoy`

- [ ] Empty or disposable? Full restore **overwrites** the staging database (project is **not** deleted).
- [ ] Compute/disk sized for prod data volume (scale up before restore if needed).
- [ ] **Network restrictions:** allow only operator IPs / VPN (keep private).
- [ ] Confirm **no** production API keys in staging Dashboard yet.

### Repo guards (keep using)

All **write** scripts must continue to call:

- `tradetraxs_assert_staging_live_database` → allowlist `hxlcvffvyadlxcsqxxoy`, block `fobudrkniacatvilbofw`
- Production export/backup uses **separate** env (`TRADETRAXS_PRODUCTION_DATABASE_URL`) and must **not** set `TRADETRAXS_ENV=staging`

Extend operational discipline: **before every manual `psql`**, run `\conninfo` and verify host/ref.

---

## 3. Database backup / restore plan (full copy)

Goal: **all application schemas**, **all rows**, **auth schema users**, **RLS**, **RPCs**, **triggers**, **publication membership**, **`supabase_migrations` history**, **roles/grants** (as supported by backup method).

### Option B — Supabase CLI (recommended for existing staging ref)

Prerequisites: [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started), `supabase login`, production **database password** (backup), staging **database password** (restore).

**Phase B1 — Backup production (no staging env flags)**

```bash
unset TRADETRAXS_ENV LOADTEST_ENV
export SUPABASE_ACCESS_TOKEN='…'   # dashboard account token

# Link only for dump, or use --db-url (prefer explicit URLs + guards)
supabase link --project-ref fobudrkniacatvilbofw   # optional; unlink after if policy requires

mkdir -p supabase/staging/artifacts/full-clone
supabase db dump \
  --project-ref fobudrkniacatvilbofw \
  --file supabase/staging/artifacts/full-clone/prod_roles.sql --role-only

supabase db dump \
  --project-ref fobudrkniacatvilbofw \
  --file supabase/staging/artifacts/full-clone/prod_schema.sql

supabase db dump \
  --project-ref fobudrkniacatvilbofw \
  --file supabase/staging/artifacts/full-clone/prod_data.sql \
  --use-copy \
  --data-only
```

Follow Supabase’s [backup-restore](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore) ordering: **roles → schema → data** (and any extra files they document for Auth/storage schemas).

**Phase B2 — Prepare staging database**

- Pause **all** app workers, crons, and webhooks pointing at staging (see §8).
- In staging Dashboard: note extensions; match production extension set **before** restore if the guide requires it.
- If staging already has schema/data: plan **destructive** reset (truncate/drop public + re-import, or restore to fresh project). Supabase may require an empty database or use their documented restore user.

**Phase B3 — Restore to staging (writes only on hxlcvffvyadlxcsqxxoy)**

```bash
export TRADETRAXS_ENV=staging
export TRADETRAXS_STAGING_PROJECT_REF=hxlcvffvyadlxcsqxxoy
export TRADETRAXS_STAGING_DATABASE_URL='postgresql://postgres.hxlcvffvyadlxcsqxxoy:…@db.hxlcvffvyadlxcsqxxoy.supabase.co:5432/postgres'

# Manual identity check (required every session):
psql "$TRADETRAXS_STAGING_DATABASE_URL" -c '\conninfo'

# Apply in order per Supabase docs (ON_ERROR_STOP=1):
psql "$TRADETRAXS_STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/staging/artifacts/full-clone/prod_roles.sql
psql "$TRADETRAXS_STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/staging/artifacts/full-clone/prod_schema.sql
psql "$TRADETRAXS_STAGING_DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/staging/artifacts/full-clone/prod_data.sql
```

**Post-restore SQL (staging only)**

- Reset **custom role passwords** if logical backup omitted them ([backups doc](https://supabase.com/docs/guides/platform/backups)).
- **Disable dangerous extensions’ jobs** (clone doc): `pg_cron`, `pg_net`, wrappers — unschedule cron jobs or disable extension until side effects are gated.
- Re-run `NOTIFY pgrst, 'reload schema';` if needed.

### Option C — Dashboard physical/logical `.backup`

1. Production → **Database → Backups** → download backup (or PITR point).
2. Follow [dashboard restore](https://supabase.com/docs/guides/platform/migrating-within-supabase/dashboard-restore) **into staging connection string** (not into production).

---

## 4. Storage buckets and files

Database backups **do not** include Storage object bytes ([backups doc](https://supabase.com/docs/guides/platform/backups)).

After DB restore:

1. Ensure buckets exist on staging (metadata may already be in `storage.buckets` from DB copy).
2. Copy objects **prod → staging** with a dedicated tool/script using **service role** keys (never commit):

   - List: Storage API `list` per bucket (`avatars`, `screenshots`, `profile_posts`, `stories`, `reels`, `csv-support`, `message-audio`, `draft-media`, `demo-media`, `bug-reports`, `email-assets`, `group-avatars`).
   - Copy preserving **paths** so `storage.objects` rows remain valid.
   - Verify counts / spot-check hashes for large buckets.

3. Staging Storage CORS: allow **staging web origin only**.

---

## 5. Edge Functions, Auth, Realtime, extensions

| Component | Action on staging |
|-----------|-------------------|
| **Edge Functions** | `supabase functions deploy guest-session --project-ref hxlcvffvyadlxcsqxxoy` with **staging** secrets |
| **Auth settings** | Reconfigure Site URL, redirect URLs, **staging OAuth** client IDs/secrets (Apple, Google, etc.) — **do not** reuse production OAuth secrets |
| **API keys** | New anon/service keys from staging Dashboard only |
| **JWT / SMTP** | Staging SMTP or **disable** outbound auth emails (§8) |
| **Realtime** | Usually follows DB publication rows; verify `supabase_realtime` membership |
| **Extensions** | Match production; disable external-facing jobs until gated |

---

## 6. Vault and production-specific secrets

- **`vault.secrets` (Supabase Vault):** If used on production, secrets are **environment-specific**. After DB copy, **rotate or delete** vault entries on staging and replace with staging/test secrets. Do not assume copied vault ciphertext works on staging.
- **`broker_integration_connections` / tokens:** Copied rows may contain **live broker OAuth tokens** — disable auto-sync and workers on staging (§8) or scrub tokens before go-live.
- **Stripe IDs** in `profiles` / billing tables: use **Stripe test mode** keys on staging; expect mismatched customer IDs unless you run a separate Stripe test account migration (usually **do not** point staging at live Stripe).

---

## 7. Preserve identifiers

Full logical/physical restore preserves **primary keys and `auth.users.id`**, so FK relationships remain intact. Do **not** run seed scripts that reassign UUIDs. Avoid `forward_migrations.manifest` re-apply on top of a full clone unless you know migrations are **ahead** of backup snapshot.

---

## 8. Side-effect kill switch (before any staging traffic)

Configure **staging-only** env (Vercel preview / internal host). **Block before restore completes:**

| System | Risk | Staging action |
|--------|------|----------------|
| **Supabase Auth email** | Password reset / magic links to real users | Disable SMTP or use sink; turn off mail in Auth settings for testing |
| **Vercel crons** | `vercel.json`: Apple revoke, expired stories, weekly reports | Disable crons on staging deployment or remove `CRON_SECRET` |
| **Stripe** | Webhooks / charges | `STRIPE_SECRET_KEY` = test mode; **no** production webhook URL; disable billing routes or guard with `STAGING` flag |
| **Tradovate/Rithmic worker** | Live sync | Do not run `services/tradovate-sync-worker` against staging; set `auto_sync_enabled` false in DB or env gate |
| **Push (APNs/FCM)** | Notifications to real devices | Omit prod push keys; use sandbox or disable |
| **OpenAI / psychology** | Cost + data leakage | Staging API key + rate limits |
| **Edge Functions** | Service role against copied data | Deploy with staging URL/keys; no production `SHOWCASE_USER_ID` |
| **pg_cron / pg_net** | Scheduled HTTP/SQL | Unschedule jobs on staging DB post-restore |
| **Load tests** | Public exposure of PII | **Do not** run k6 against full clone with anon key on public internet |

Access control:

- Supabase **network restrictions** on staging.
- No production domain in Auth redirect URLs.
- Internal VPN / IP allowlist for staging web app.

---

## 9. Verification checklist (after restore, before team access)

### Database

- [ ] `\conninfo` shows `db.hxlcvffvyadlxcsqxxoy.supabase.co`
- [ ] Row counts within expected range vs production (profiles, trades, messages, posts)
- [ ] `auth.users` count matches expectation; sample login only with **test account** you control
- [ ] `public.handle_new_user` + `on_auth_user_created` present
- [ ] RLS enabled on public tables (spot-check)
- [ ] Critical RPCs exist (`rpc_v1_session_bootstrap`, etc.)
- [ ] `supabase_migrations.schema_migrations` matches production at backup time

### Storage

- [ ] All 12 buckets present
- [ ] Random sample of objects downloadable on staging
- [ ] Broken object rate acceptable (note keys that 404)

### App / integrations

- [ ] Staging web/iOS env points to `hxlcvffvyadlxcsqxxoy` keys only
- [ ] Stripe test mode verified (no live charge)
- [ ] Broker worker **off**; connection test fails closed or uses sandbox
- [ ] Crons disabled
- [ ] No email/push sent during smoke test (monitor logs)

### Legal / privacy

- [ ] Staging access limited to operators under NDA
- [ ] No load tests or public signup links on copied data

---

## 10. Credentials you must provide (never commit)

| Credential | Used for |
|------------|----------|
| Supabase **account** access token | CLI, Management API, optional backup list |
| Production **database** password / connection string | **Backup only** (prefer read-only role for audits; full role for dump per Supabase docs) |
| Staging **database** password / connection string | Restore + verify (guarded writes) |
| Production + staging **service role** keys | Storage object copy (secure machine only) |
| Staging **anon** key | App smoke tests (internal) |
| Stripe **test** keys + webhook secret | Staging billing |
| OAuth **staging** client secrets | Auth providers |
| Edge Function secrets (`SHOWCASE_USER_ID`, etc.) | Staging function deploy |

**Do not** put production DB URLs in `supabase/staging/.env.local`.

---

## 11. Relationship to repo schema-only tooling

- **Schema-only** path remains in `export-production-schema.sh` for sanitized baselines and CI.
- **Full clone** uses Supabase platform backup/restore + Storage copy; **deprecate** forward manifest repair until you know backup migration max vs repo HEAD.
- Update `CONFIG_CHECKLIST.md` data boundaries when switching to full clone (copied PII is expected — compensate with access controls in §8–9).

---

## 12. Suggested execution order (when approved)

1. Audit source/destination (§2).  
2. Enable side-effect kill switches on **staging app config** (§8) — even before data exists.  
3. Scale staging compute/disk if needed.  
4. Production **backup** (CLI or Dashboard) — **read-only** where possible.  
5. Restore into **`hxlcvffvyadlxcsqxxoy`** only.  
6. Post-restore: disable `pg_cron` / `pg_net` jobs; vault/broker review (§6).  
7. Storage file copy (§4).  
8. Deploy Edge Functions + Auth settings (§5).  
9. Verification (§9).  
10. Limited internal smoke test — **no load tests**.

**Production is never modified** by restore operations; only backup reads touch production.
