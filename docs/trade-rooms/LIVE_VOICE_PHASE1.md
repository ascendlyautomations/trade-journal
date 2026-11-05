# Trade Room live voice — Phase 1 (web + iOS)

Open voice channels (`live_kind = voice_open` or `voice_stage` without stage UI) using LiveKit tokens from `POST /api/livekit/token`.

## Enable a channel

```sql
update public.room_sections
set live_kind = 'voice_open'
where id = '<section-uuid>';
```

## Clients

- **Web:** `/community` — Join voice, fixed bottom bar (mute / participants / leave).
- **iOS:** Trade Room conversation — Join voice; app-wide bar via `MainTabShellView` safe area inset.

Sessions are **app-scoped** (`RoomLiveVoiceCoordinator.shared` / web store) and persist across navigation and text-channel switches until Leave or joining another voice section.

## Not in Phase 1

Stage promote UI, screen share, iOS background audio.

## Device QA (required)

Two physical devices or simulator + device with LiveKit env configured: join same voice section, bidirectional audio, mute, navigate tabs/channels without drop, leave clears mic.
