# Migration baseline and forward-only tracking

## Snapshot point (production audit: 2026-10-26)

| Field | Value |
|--------|--------|
| Production project ref | `fobudrkniacatvilbofw` |
| `supabase_migrations.schema_migrations` count | **97** rows |
| Ledger min version | `20260819210452` (`rpc_v1_session_bootstrap`) |
| Ledger max version | `20261024042226` (`achievement_payout_firm_assignment`) |

The baseline **split schema-only export** captures the **effective DDL** of production at export time. That includes:

- ~**322** repo migration files applied **before** Supabase migration tracking (March–August 2026)
- All objects from the **97** tracked migrations
- Out-of-band objects **not in any repo file** (e.g. `public.handle_new_user()`, `auth.on_auth_user_created`)

The dump **excludes** `supabase_migrations` history so staging does not inherit production’s incomplete ledger.

Re-query before each baseline export:

```sql
select version, name
from supabase_migrations.schema_migrations
order by version desc
limit 5;
```

Update `artifacts/BASELINE_SNAPSHOT.json` and this doc if the max version changes.

## Why not run all 396 migrations on an empty database?

The earliest repo file alters `public.trades`; **26+ core tables** (including `profiles`, `trades`, `accounts`, `rooms`, `messages`) have **no `CREATE TABLE` in migrations**. A greenfield `supabase db reset` from repo files alone **will fail**.

## Forward-only manifest (after baseline)

File: [`../forward_migrations.manifest`](../forward_migrations.manifest)

### Do **not** reapply (already in baseline via production)

- All local migration files with timestamp **≤ ledger max**, including files **never listed** in `schema_migrations` (legacy apply).
- Republished duplicates (same logical change, different local timestamp):

| Local file (skip) | Production ledger version |
|-------------------|---------------------------|
| `20261024043000_delete_prop_payout_restore_balance.sql` | `20261024041235` |
| `20261024044500_achievement_payout_firm_assignment.sql` | `20261024042226` |

### Apply on staging after baseline verify (**9** files)

| Order | File | Notes |
|------:|------|--------|
| 1 | `20261024150000_message_reaction_heart.sql` | Message reactions |
| 2 | `20261024163000_trade_room_moderator_permissions.sql` | Room moderators |
| 3 | `20261025180000_phase1_security_accounts_and_rooms.sql` | Accounts RLS, room join security |
| 4 | `20261026120000_phase1_security_followup.sql` | Depends on phase1 |
| 5 | `20261026140000_phase2_trading_data_integrity.sql` | Payout cycles / trading integrity |
| 6 | `20261026150000_trades_max_rr_reached.sql` | Column addition |
| 7 | `20261026160000_trades_realized_rr.sql` | Column addition |
| 8 | `20261026170000_phase3_room_ban_atomic.sql` | `rpc_v1_ban_trade_room_member` |
| 9 | `20261026180000_phase3_ledger_payout_delete_atomic.sql` | Ledger payout delete RPC |

**Dependency chain:** `25180000` → `26120000` → `26140000` → phase3 pair. Do not reorder.

### Ambiguous local files (in baseline if export is current; not in forward manifest)

These exist in the repo with timestamps **before** ledger max but **may** differ slightly from production if edited after apply. Treat baseline dump as source of truth; diff manually if you change them locally:

- `20261023163000` – `20261024033135` (prop firm / expense tracker)
- `20261019200000_rpc_v1_dashboard_bootstrap_drawdown_type.sql`
- Leaderboard / monetization flags (`20261014191053`, `20261002200000`, etc.)

If your branch changes any of these **after** baseline export, add them to `forward_migrations.manifest` or re-export baseline.

## Migration history on staging (after verification)

1. Do **not** run `supabase migration repair` until `run-verify.sh` succeeds.
2. Apply forward SQL via `apply-forward-migrations.sh`.
3. Run `run-verify.sh all`.
4. Run `mark-baseline-migrations-applied.sh` to align CLI history with reality **without** re-executing SQL.

## Rollback folder

`supabase/migrations/rollback/` is **not** part of the CLI chain. Never apply or repair-mark those files on staging.
