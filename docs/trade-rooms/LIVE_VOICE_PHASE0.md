# Trade Room live voice — Phase 0 (backend)

Phase 0 adds LiveKit token minting, stage permission updates, membership revocation disconnects, and `room_sections.live_kind`. **No iOS background audio** and **no client LiveKit UI** in this phase.

## Environment variables (server-only)

| Variable | Required | Description |
|----------|----------|-------------|
| `LIVEKIT_URL` | Yes | LiveKit server URL (e.g. `wss://….livekit.cloud`) returned to clients |
| `LIVEKIT_API_KEY` | Yes | LiveKit API key |
| `LIVEKIT_API_SECRET` | Yes | LiveKit API secret — never ship to clients |
| `LIVEKIT_OUTBOX_WEBHOOK_SECRET` | Yes (prod) | Bearer secret for outbox processor (`Authorization: Bearer …`) |
| `CRON_SECRET` | No | Fallback if `LIVEKIT_OUTBOX_WEBHOOK_SECRET` unset (legacy) |
| `LIVEKIT_MAX_PARTICIPANTS` | No | Default `25` (reserved for room create tuning) |
| `LIVEKIT_TOKEN_TTL_SECONDS` | No | JWT TTL, default `900` (15 minutes) |

Vercel Hobby does **not** run frequent crons for LiveKit. Outbox processing is **Supabase-driven** (see below).

## Database

Apply migrations:

1. `20261105133000_trade_room_livekit_phase0.sql` — `live_kind`, outbox, ban/leave triggers, bootstrap
2. `20261105160000_livekit_outbox_event_driven.sql` — pg_net insert dispatch, pg_cron retry, claim RPC

After deploy, configure the processor (once per Supabase project):

```sql
insert into private.livekit_outbox_processor_config (id, bff_process_url, bearer_secret)
values (
  1,
  'https://www.tradetraxs.com/api/internal/livekit/process-outbox',
  '<same value as LIVEKIT_OUTBOX_WEBHOOK_SECRET on Vercel>'
)
on conflict (id) do update set
  bff_process_url = excluded.bff_process_url,
  bearer_secret = excluded.bearer_secret,
  updated_at = timezone('utc', now());
```

**Flow**

- Ban / kick / leave → row in `room_livekit_disconnect_outbox` → **AFTER INSERT trigger** → `pg_net.http_post` → BFF processes that row (or batch on cron).
- **pg_cron** every 5 minutes retries pending/failed rows (same endpoint, empty body = batch claim).
- Processing re-checks `room_livekit_should_disconnect` so reinstated members are not disconnected by stale rows.
- Claims use `FOR UPDATE SKIP LOCKED` + 5-minute lease (`processing_claimed_at`).

Optional: Supabase Dashboard **Database Webhook** on `room_livekit_disconnect_outbox` INSERT can mirror the trigger if pg_net is disabled in an environment.

## API

| Method | Path | Auth | Purpose |
|--------|------|------|---------|
| `POST` | `/api/livekit/token` | Bearer / cookie | Mint short-lived join token |
| `POST` | `/api/livekit/stage/promote` | Member mod/owner | Grant mic on stage channel |
| `POST` | `/api/livekit/stage/demote` | Member mod/owner | Revoke mic on stage channel |
| `POST` | `/api/livekit/disconnect-member` | Self or mod | Immediate `RemoveParticipant` (web mod ban/kick) |
| `POST` | `/api/internal/livekit/process-outbox` | `LIVEKIT_OUTBOX_WEBHOOK_SECRET` | Process outbox (Supabase pg_net / pg_cron) |
| `GET` | `/api/cron/livekit-disconnect-outbox` | Same secret | Manual batch (legacy path) |

LiveKit room names use `tt/{roomId}/{sectionId}` (UUID-safe).

Token body: `{ "roomId": "uuid", "sectionId": "uuid" }`.

Outbox processor body: `{ "outboxId": "uuid", "source": "pg_trigger" }` (optional; omit for batch).

## Session lifecycle (planned clients)

- Live voice persists across navigation and text-channel switches until **Leave** or joining another voice section.
- Persistent in-app **voice bar** (mute + leave) binds to an app-scoped session controller (iOS Phase 1+).
- Audio policy: `lib/audio/tradeTraxsAudioPolicy.ts` — live voice preempts voice notes and feed video.

## Revocation

Ban, kick, and leave enqueue outbox rows. **Immediate** disconnect on web mod ban/kick via `/api/livekit/disconnect-member` when the client calls it after success. All paths still enqueue for retry.

## App Store

Background audio justification and `UIBackgroundModes` audio are **deferred** to iOS Phase 2.
