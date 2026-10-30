# Staging side-effect gates (full clone)

Apply **before** staging app/workers receive traffic. Copied production data includes real users, tokens, and billing IDs.

## Supabase Dashboard (staging `hxlcvffvyadlxcsqxxoy`)

- [ ] **Auth → Email:** disable SMTP or use a sink; block password reset / magic link emails to real addresses
- [ ] **Auth → URL configuration:** Site URL and redirects → **staging host only** (never tradetraxs.com production)
- [ ] **OAuth:** staging Apple/Google client IDs and secrets (do not reuse production OAuth apps)
- [ ] **API keys:** use staging anon/service keys only in deployments
- [ ] **Network restrictions:** limit DB/API to operator IPs or VPN
- [ ] **Database webhooks / Edge Function hooks:** disable until reviewed

## Hosting (Vercel / staging web)

- [ ] `NEXT_PUBLIC_SUPABASE_URL` → staging project
- [ ] `SUPABASE_SERVICE_ROLE_KEY` → staging only
- [ ] **Stripe:** `STRIPE_SECRET_KEY` = **test mode**; webhook endpoint on staging with test secret; no production webhook URL
- [ ] **Crons disabled** (`vercel.json`): `/api/cron/apple-sign-in-revoke`, `expired-stories`, `weekly-trading-reports` — remove `CRON_SECRET` or do not deploy crons to staging
- [ ] Email/push providers: omit production keys or use sandbox

## Workers

- [ ] **Do not run** `services/tradovate-sync-worker` against staging until broker sandbox or tokens scrubbed
- [ ] DB hardening (`post-restore-hardening.sql`) sets `auto_sync_enabled = false` — verify

## Database (after restore)

- [ ] Run `post-restore-hardening.sql` (included in restore script)
- [ ] If using **Supabase Vault:** copy pgsodium root key per [backup-restore](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore) or re-secrets staging vault entries
- [ ] Review `pg_net` / external wrappers if enabled on production

## Testing policy

- [ ] No public load tests (`loadtest/`) against copied customer data
- [ ] No anon signup links on the public internet
- [ ] Internal operators only under access policy
