# Trade Room interactive livestream (web + iOS viewing)

Dedicated LiveKit room per Trade Room: `tt/{roomId}/broadcast`. **General Voice** remains `tt/{roomId}/voice` and is not used for stream audio.

## Database

Apply migrations (in order):

1. `supabase/migrations/20261105193000_trade_room_live_broadcast.sql`
2. `supabase/migrations/20261105210000_trade_room_broadcast_voice_mode.sql`
3. `supabase/migrations/20261107160000_trade_room_broadcast_obs_ingress.sql`
4. `supabase/migrations/20261107180000_trade_room_broadcast_video_source_obs.sql` (`video_source` may be `obs` for OBS-only encoder sessions)
5. `supabase/migrations/20261107190000_trade_room_broadcast_visibility.sql` — `visibility` (`public` \| `preparing`) and `go_live_notified_at` (dedupe one fan-out when going public)

Session metadata: `voice_mode` (`broadcast_only` | `open_voice`), `video_source` (`screen` | `camera` | `obs`), optional OBS fields: `broadcast_source`, `primary_media_publisher_identity`, `livekit_ingress_id`, `ingress_status_snapshot` (RTMP stream keys are never stored). **OBS two-stage:** new rows use `visibility=preparing` until the host calls publish; viewers must not treat the session as discoverable until `visibility=public`.

## OBS two-stage (Instagram Producer–style)

1. **Start (OBS):** `POST /api/livekit/broadcast/start` with `videoSource: obs` creates a `preparing` session, ingress, and host token. No go-live push notifications.
2. **Prepare:** Host configures OBS; optional private preview in the broadcast UI. Viewer token routes and interactive snapshot return 404 / null for non-hosts while `preparing`.
3. **Go live:** `POST /api/livekit/broadcast/publish` (broadcaster only) flips `visibility` to `public`, sets `go_live_notified_at`, and runs member notifications **once**.
4. **Browser sources** still start as `public` immediately (unchanged).

## API (authenticated BFF)

| Route | Purpose |
|-------|---------|
| `POST /api/livekit/broadcast/start` | Body: `roomId`, `voiceMode`, `videoSource` (`screen` \| `camera` \| `obs`). Browser: publisher token with screen/camera + mic. `obs`: mic-only host token; RTMP ingress via `obs/credentials`. |
| `POST /api/livekit/broadcast/stop` | Broadcaster or moderator ends session |
| `POST /api/livekit/broadcast/token` | Member viewer token (subscribe + chat data, no publish) |
| `POST /api/livekit/broadcast/join-conversation` | Open-voice only: server `updateParticipant` + conversation mic token |
| `POST /api/livekit/broadcast/leave-conversation` | Revoke mic + viewer token |
| `GET /api/livekit/broadcast/status?roomId=` | **`live`**: active session row visible to this user (for the broadcaster, includes OBS `preparing`). **`publicLive`**: discoverable / viewer stream (false while OBS is preparing). Also: `visibility`, broadcaster, voice mode, viewer count, `broadcastSource`, `primaryMediaPublisherIdentity`, `hostConnected`, `primaryMediaPublisherConnected` (full poll). `&lite=1` = cheap poll (session row + broadcast source fields; merges with last full response). `&reconcile=1` = owner may end abandoned session (OBS: does not end while ingress is waiting for encoder). |
| `POST /api/livekit/broadcast/publish` | Broadcaster only. Body: `roomId`. Requires encoder connected; sets `visibility=public` and triggers go-live notifications once. |
| `POST /api/livekit/broadcast/obs/credentials` | Broadcaster only. Body: `roomId`, `sessionId`. Creates LiveKit RTMP ingress; returns `rtmpUrl` + `streamKey` once (not logged server-side). |
| `GET /api/livekit/broadcast/obs/status?roomId=&sessionId=` | Broadcaster only. Ingress + presence summary; no secrets. |
| `POST /api/livekit/broadcast/obs/revoke` | Broadcaster only. Body: `roomId`, `sessionId`. Deletes ingress and clears metadata (idempotent). |
| `POST /api/livekit/webhook` | LiveKit Cloud lifecycle cleanup |

Live chat: LiveKit data topic `tt_broadcast_chat` (ephemeral, not stored in Supabase).

## Local QA

### Web

1. Apply migrations to your Supabase project; set LiveKit env vars. **Ingress:** LiveKit Cloud project with Ingress enabled, or self-hosted LiveKit with the Ingress service wired to the same API URL the server uses.
2. Owner/moderator: **Go Live** → setup dialog (Screen Share, Camera Only, or **OBS Studio**). Browser sources share screen or camera; **OBS** shows RTMP URL + stream key (host-only) and does not require browser video capture. Preview and viewers attach video/audio to the ingress program identity (`primaryMediaPublisherIdentity`).
3. Member: **Watch stream** → video + live chat; if `open_voice`, use **Join conversation** (explicit mic grant).
4. Confirm stream copy does **not** mention General Voice; optional warning if General Voice is already connected.
5. Stop stream → chat clears; new go-live starts fresh session.

### iOS (viewing only)

1. Open Trade Room conversation → **LIVE** banner when status poll sees active broadcast.
2. **Watch Live** → native video + chat; for OBS broadcasts, video/audio follow `primaryMediaPublisherIdentity` from the status/token response (not only the host UUID).
3. General Voice bar unchanged; playback uses playback-only session when voice is not active.

### Tests

```bash
npm run test:livekit-phase0
```
