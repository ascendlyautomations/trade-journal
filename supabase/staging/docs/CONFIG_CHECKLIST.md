# Staging configuration checklist

Staging project **`hxlcvffvyadlxcsqxxoy`** · Production blocklist **`fobudrkniacatvilbofw`**

## Full clone (primary)

- [ ] Read [`../full-clone/README.md`](../full-clone/README.md) and [`SIDE_EFFECT_GATES.md`](SIDE_EFFECT_GATES.md)
- [ ] Staging plan/disk fits production DB size (**Free tier 500 MB limit**)
- [ ] `full-clone/.env.local` or shell vars configured (no secrets in git)
- [ ] Production backup: `backup-production-database.sh` (read-only dump)
- [ ] Staging rollback snapshot before restore
- [ ] Restore: `TRADETRAXS_FULL_CLONE_CONFIRM=yes` + `restore-staging-database.sh`
- [ ] Storage object copy (separate from DB backup)
- [ ] Edge Function `guest-session` deployed to staging
- [ ] Auth/OAuth/Stripe **test** / staging keys only
- [ ] Crons, broker worker, email, push **gated** before traffic

## PostgreSQL clients

`brew install libpq` — scripts prepend `/opt/homebrew/opt/libpq/bin`.

## Legacy schema-only (optional)

- [ ] `export-production-schema.sh` / `restore-staging-schema.sh` / `forward_migrations.manifest`

## Guards

- [ ] `TRADETRAXS_STAGING_PROJECT_REF=hxlcvffvyadlxcsqxxoy`
- [ ] Production dumps never run with `TRADETRAXS_ENV=staging`
- [ ] `\conninfo` verified before manual `psql`
