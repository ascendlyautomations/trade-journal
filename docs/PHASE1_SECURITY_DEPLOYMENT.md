# Phase 1 security — deployment order

Apply migrations in timestamp order:

1. `20261025180000_phase1_security_accounts_and_rooms.sql`
2. `20261026120000_phase1_security_followup.sql`
3. `20261026140000_phase2_trading_data_integrity.sql` (payout RPC, achievement delete, CSV dedupe — independent of Phase 1 security)

## Recommended release sequence

1. **Staging:** Apply both migrations; run policy inspection SQL below; smoke-test accounts, public rooms, private invite (Web + store iOS build), kick/ban/rejoin.
2. **Web:** Deploy client with `fetchTradeRoomInviteLookup` (can ship before or with prod migration; RPC is additive after migration 1).
3. **Production database:** Apply migrations 1 then 2 in one maintenance window (or staging first, then prod after sign-off).
4. **iOS:** Follow-up migration 2 restores **direct `rooms` SELECT by slug** for **private community** rows so **currently released** iOS keeps working. Ship the invite-RPC fallback build when convenient (strictest client path).

**Do not** apply migration 1 alone on production if store iOS must keep private slug links and you cannot ship Web/iOS immediately — migration 2 fixes that gap; apply 1+2 together.

## Accounts RLS — inspect before deploy

Run on the target database (staging clone or production read-only):

```sql
-- RLS enabled?
select c.relname, c.relrowsecurity, c.relforcerowsecurity
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relname = 'accounts';

-- All policies on public.accounts (check for extra permissive rows)
select
  policyname,
  permissive,
  roles,
  cmd,
  qual as using_expression,
  with_check
from pg_policies
where schemaname = 'public' and tablename = 'accounts'
order by policyname;

-- Permissive policies with overly broad USING (manual review)
select policyname, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'accounts'
  and (
    qual is null
    or qual ilike '%true%'
    or qual not ilike '%auth.uid()%'
  );
```

After migration, expect **only** `accounts_select_own`, `accounts_insert_own`, `accounts_update_own`, `accounts_delete_own`, each scoped with `user_id = auth.uid()`. Drop any remaining legacy policies manually before relying on RLS.

## Known tradeoffs (follow-up migration 2)

- **Private slug enumeration:** `rooms_select_invite` allows authenticated clients to read all private community rooms that have a slug (same class of issue as pre–Phase 1 invite policy, but **not** all rooms via `rooms_select_profile_public`).
- **Kick vs ban:** Kicks set `owner_removed_at`; bans use `room_bans` plus join-request invalidation. Voluntary leave does not set `owner_removed_at`.
