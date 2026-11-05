# Trade Room live voice — Phase 1 (web + iOS)

Each Trade Room has **one shared voice channel** — **General Voice** — backed by LiveKit room names `tt/{roomId}/voice` and tokens from `POST /api/livekit/token` with `{ "roomId": "uuid" }`.

## Database

- `rooms.live_voice_kind`: `voice_open` (default), `voice_stage`, or `off`
- Text channels stay in `room_sections` with `live_kind = text` (no per-section voice rows)

## Clients

- **Web:** `/community` — General Voice in the room sidebar (separate from text channels); fixed bottom bar while connected.
- **iOS:** Trade Room conversation — General Voice row above the text channel switcher; app-wide bar via `MainTabShellView`.

Voice sessions are **app-scoped** and persist across text-channel switches and navigation until Leave or joining another Trade Room’s voice.

## Not in Phase 1

Stage promote UI, screen share, iOS background audio.

## Device QA (required)

Two devices with LiveKit env: join the same Trade Room General Voice from different text channels, bidirectional audio, mute, navigate without drop, leave clears mic; no mic → listen-only with message (no disconnect loop).
