# Trade Room interactive livestream (web + iOS viewing)

Dedicated LiveKit room per Trade Room: `tt/{roomId}/broadcast`. **General Voice** remains `tt/{roomId}/voice` and is not used for stream audio.

## Database

Apply migrations (in order):

1. `supabase/migrations/20261105193000_trade_room_live_broadcast.sql`
2. `supabase/migrations/20261105210000_trade_room_broadcast_voice_mode.sql`

Session metadata: `voice_mode` (`broadcast_only` | `open_voice`), `video_source` (`screen` | `camera`).

## API (authenticated BFF)

| Route | Purpose |
|-------|---------|
| `POST /api/livekit/broadcast/start` | Body: `roomId`, `voiceMode`, `videoSource`. Publisher token (screen, camera, mic). |
| `POST /api/livekit/broadcast/stop` | Broadcaster or moderator ends session |
| `POST /api/livekit/broadcast/token` | Member viewer token (subscribe + chat data, no publish) |
| `POST /api/livekit/broadcast/join-conversation` | Open-voice only: server `updateParticipant` + conversation mic token |
| `POST /api/livekit/broadcast/leave-conversation` | Revoke mic + viewer token |
| `GET /api/livekit/broadcast/status?roomId=` | Live flag, broadcaster, voice mode, viewer count |
| `POST /api/livekit/webhook` | LiveKit Cloud lifecycle cleanup |

Live chat: LiveKit data topic `tt_broadcast_chat` (ephemeral, not stored in Supabase).

## Local QA

### Web

1. Apply migrations to your Supabase project; set LiveKit env vars.
2. Owner/moderator: **Go Live** → setup dialog (source, voice mode, mic) → share screen or camera.
3. Member: **Watch stream** → video + live chat; if `open_voice`, use **Join conversation** (explicit mic grant).
4. Confirm stream copy does **not** mention General Voice; optional warning if General Voice is already connected.
5. Stop stream → chat clears; new go-live starts fresh session.

### iOS (viewing only)

1. Open Trade Room conversation → **LIVE** banner when status poll sees active broadcast.
2. **Watch Live** → native video + chat (send requires wiring `userId` from session in a follow-up if nil).
3. General Voice bar unchanged; playback uses playback-only session when voice is not active.

### Tests

```bash
npm run test:livekit-phase0
```
