# TradeTraxs Notification System — Production Cleanup & Architecture Audit

**Date:** 2026-07-27 (revised: Activity vs Messaging split)  
**Scope:** Cleanup of temporary iOS push verification code + architecture planning only.  
**Status:** Phase 1 cleanup applied in repo. Architecture guidance below — **not implemented**.

---

## Phase 1 — Cleanup summary (completed)

### Removed
- `[apns:temp]` / verbose APNs config logging (`lib/server/push/apns.ts`)
- `[api/push/register:temp]` diagnostics (`app/api/push/register/route.ts`)
- `[ios-push:temp]` client registration diagnostics (`lib/nativeIosPush.ts`)
- Temporary Settings **Test Push Notification** UI (`SettingsTestPushButton.tsx` + Settings wiring)
- Temporary route `app/api/push/test/route.ts`
- Temporary `env` boolean dump on `GET /api/push/status`

### Kept (production infrastructure)
- APNs service (`lib/server/push/apns.ts`)
- Delivery pipeline (`deliverPushNotification.ts`, `pushCopy.ts`)
- Register / unregister / status endpoints
- `device_push_tokens` storage + migration
- Native registration (`lib/nativeIosPush.ts`, `NativeIosPushRegistration`)
- Concise `console.error` on real failures only

---

## Architecture revision — Activity vs Messaging (Instagram model)

TradeTraxs should treat **Activity** and **Messaging** as two products that share APNs infrastructure, not one inbox.

| | **System 1 — Activity** | **System 2 — Messaging** |
|--|-------------------------|---------------------------|
| **Purpose** | Social + account events that stay visible | Ephemeral alert that a conversation needs attention |
| **Persisted where** | `public.notifications` → `/notifications` | Conversation / room unread state only |
| **Push** | After Activity row (existing pipeline) | **Directly from messaging** — no Activity row required |
| **Dismiss push** | Event still in Activity feed | Unread stays in Messages / Rooms only |
| **Badge** | Activity unread count | Messages / rooms unread count (independent) |

**Mentions in Trade Rooms are the exception:** they are Activity (persistent) **and** push, with a deep link to the exact message — same idea as Instagram @mentions remaining in Activity.

### Audit — what messaging does today

| Event | Flows through Activity (`notifications`) today? | Target |
|-------|--------------------------------------------------|--------|
| Trade room **normal** message | **Yes** — `room_message` via `createRoomMessageNotifications` → `/api/notifications/room-message`; included in `NOTIFICATION_INBOX_TYPES` + Navbar badge | **Remove from Activity**; push-only from messaging |
| Trade room **@mention** | Partially — room fanout may create `room_message` rows for all members; **no dedicated mention Activity path** (`room_mentions_enabled` largely unused) | **Activity + push** for mentioned user(s) only |
| DM new message | **No** Activity insert (pref `direct_messages_enabled` unused for create) | Push-only from messaging; never Activity |
| Room join | Yes (`room_join`) | Keep in Activity (social/membership, not chat spam) |
| Room announcements (future) | N/A | Activity (optional) |

### Events to remove from the Activity pipeline (plan only)

1. Stop inserting `type = 'room_message'` for ordinary room chat (or stop counting/showing them in Activity even if legacy rows remain).
2. Do **not** add DM rows to `notifications` for ordinary DMs.
3. Keep using shared `sendApnsAlert` / `device_push_tokens` for messaging pushes without requiring an Activity insert first.

### Schema

**No immediate schema change required.**  
Unread for DMs/rooms already lives on conversations / room membership. Eventually optional: drop or stop writing `room_message` Activity rows; no new table needed for the split. A future `notifications.type` for `room_mention` (or content flag) would help clarity when implementing — not required to adopt this architecture.

---

## 1. Updated notification flow

### System 1 — Activity (persistent)

```
User action (like, comment, follow, room mention, achievement, billing, …)
        │
        ▼
ActivityNotificationService.create(...)
        │
        ├─► Prefs + blocks + mutes (as applicable)
        ├─► INSERT public.notifications
        ├─► Realtime → Activity badge + /notifications
        └─► scheduleIosPushDelivery (optional per type)
              badge = Activity unread only
              href = Activity deep link
```

### System 2 — Messaging (no Activity row)

```
DM or Trade Room message inserted
        │
        ▼
MessagingPushService.notifyParticipants(...)
        │
        ├─► Skip self, muted conversation/room/channel, blocked users
        ├─► Skip if messaging push pref off
        ├─► Does NOT insert into public.notifications
        ├─► sendApnsAlert (shared APNs infra)
        │     badge = Messages unread (per app-icon policy)
        │     href = /messages?c=… or /community?room=…&message=…
        └─► Unread remains solely in Messages / Rooms UI if push dismissed
```

### Room @mention (hybrid)

```
Room message contains @user
        │
        ├─► Non-mentioned members: Messaging push only (if prefs/mutes allow)
        │     — NO Activity row for ordinary chat
        │
        └─► Mentioned user(s):
              Activity INSERT (visible in /notifications)
              + Push with deep link to that message
```

### Shared infrastructure

- `device_push_tokens`, APNs JWT/send, native tap → `data.href`
- Preference master switch may still gate both systems
- Separate preference keys: Activity categories vs Direct Messages / Room Messages / Room Mentions

---

## 2. Updated event classification

### Activity feed (persistent) — YES

| Category | Examples |
|----------|----------|
| Social | Trade/post/reel likes; trade/post comments; replies; **mentions** (feed + **room @mentions**); new followers; follow requests; follow accepted |
| Achievements | Unlocks, milestones, rankings, prop progress; engagement on achievement posts |
| Trading / product | AI analysis complete; import complete; trading report; journal/streak/recap (future) |
| Account | Creator events; affiliate referral/commission; trial ending; payment failed; security alerts |
| System | Announcements, maintenance, product updates |
| Rooms (non-chat) | Room joins; **optional** room announcements / pins / invites / ownership |
| **Not** Activity | Ordinary DM body; ordinary Trade Room chat lines |

### Messaging only (push + unread in Messages) — NO Activity row

| Category | Examples |
|----------|----------|
| Direct Messages | New message, attachments, thread replies (as chat) |
| Trade Rooms | New room message (non-mention) |

### Hybrid

| Event | Activity | Messaging push |
|-------|----------|----------------|
| Room @mention | Yes | Yes |
| Room announcement | Yes (optional) | Optional |

---

## 3. Updated badge strategy

| Surface | Counts | Must not include |
|---------|--------|------------------|
| **Activity** (Navbar bell / `/notifications`) | Unread `notifications` in Activity types only | Ordinary `room_message` chat; DMs |
| **Messages** | Unread conversations (existing) | Activity likes/follows |
| **App icon** | Recommended: **Activity unread + Messages unread** (sum of two independent sources) | Never inflate Activity by storing DMs/room chat in `notifications` |

**Today:** `NOTIFICATION_INBOX_TYPES` includes `room_message`, so room chat inflates the Activity badge. **Target:** remove ordinary `room_message` from inbox types; keep `room_join` and future room-mention Activity type in Activity.

**Independence rule:** Activity unread `12` and Messages unread `3` never derive from each other.

**Push `aps.badge`:**  
- Activity pushes → badge from Activity unread (or combined icon policy).  
- Messaging pushes → badge from Messages unread (or combined).  
Do not use Activity unread when sending a DM/room-chat push.

---

## 4. Updated deep-link strategy

| Source | Destination | IDs | Fallback if dismiss push |
|--------|-------------|-----|---------------------------|
| Activity like/comment | Feed entity | post/trade/reel/… | Still in `/notifications` |
| Activity follow / request | Profile | user id | Still in `/notifications` |
| Activity room mention | Room message | room slug, message id | Still in `/notifications` → same deep link |
| Activity room join | Room | room slug | Still in `/notifications` |
| Messaging DM push | Conversation | conversation id | Unread in Messages only |
| Messaging room chat push | Room thread | room slug, message id | Unread in room only |
| Affiliate / report / billing | Respective screens | as today | Still in Activity |

Native: same Capacitor `data.href` mechanism; messaging hrefs must **not** open `/notifications`.

---

## 5. Updated implementation order

| Priority | Work | Notes |
|----------|------|-------|
| **P0** | Define Activity allowlist excluding ordinary `room_message` / DM | Documented here |
| **P0** | Stop writing Activity rows for ordinary room messages; add MessagingPush from room send path | Largest Instagram-alignment change |
| **P0** | Room @mention → Activity + push (deep link to message) | Hybrid |
| **P0** | DM MessagingPush only (no Activity insert) | Do **not** wire DMs into `notifications` |
| **P0** | Split badge queries (Activity vs Messages); fix `aps.badge` policy | |
| **P1** | Central ActivityNotificationService (wrap existing social/account creators) | |
| **P1** | `user_blocks` on Activity + Messaging push | |
| **P1** | Follow accepted, achievement unlock, billing Activity events | |
| **P2** | Outbox for room messaging push fanout | Scale |
| **P2** | Reactions / stories / shares as Activity | |
| **P3** | System broadcasts; email on Activity | |

**Explicitly deprecated from prior plan:** “Wire DM notifications into `public.notifications`.”

---

## 1b. Current (as-built) architecture — snapshot

```
User action (like, comment, follow, room message, …)
        │
        ▼
Feature-specific creator (lib/*Notification*.ts)
        │
        ▼
POST /api/notifications/<type>
        │
        ├─► INSERT public.notifications
        └─► scheduleIosPushDelivery
```

Realtime: `notif-shared-{userId}` → Navbar badge (today includes `room_message`).

### Core tables
| Table | Role |
|-------|------|
| `notifications` | Activity inbox (today also holds `room_message`) |
| `notification_preferences` | Per-user toggles |
| `device_push_tokens` | Shared APNs tokens for Activity + Messaging |
| `room_members.notification_enabled` | Per-room mute |
| `room_member_channel_preferences` | Per-channel mute |
| `conversation_member_preferences` | DM mute / unread |

---

## 2b. Existing strengths

- Strong Activity table + dedupe for social types
- Preference row + master switch
- Shared APNs stack ready for Messaging-only pushes
- Room/channel mutes already exist (repurpose for Messaging push gates)
- DM unread already separate from Activity (good foundation for the split)
- Self-notify blocked; invalid token prune exists

---

## 3b. Existing weaknesses (relative to this model)

- **`room_message` is in the Activity feed and badge** — chat noise unlike Instagram
- No Messaging-only push path (room push today follows Activity insert)
- DM push missing; prior plan wrongly aimed DMs at Activity
- Social paths lack block checks
- Room fanout N+1 on request path
- Pref toggles for DMs / room mentions not aligned with two-system design

---

## 4b. Missing types (reclassified)

### Activity — implement / keep
Social likes/comments/replies/mentions; followers; follow request + accepted; achievement unlock + engagement; affiliate; trading report; AI/import; trial/payment; security; system; room join; **room @mention**; optional room announcements.

### Messaging — push only (no Activity)
DM new message; ordinary Trade Room messages.

### Pref wiring
`direct_messages_enabled` → Messaging push only.  
`room_messages_enabled` → Messaging push only.  
`room_mentions_enabled` → Activity + push.  
`room_joins_enabled` → Activity.

---

## 5b. Missing infrastructure (updated)

1. **ActivityNotificationService** — inbox insert + optional Activity push  
2. **MessagingPushService** — push without inbox insert  
3. **Stop / migrate ordinary `room_message` Activity writes**  
4. **Room mention Activity creator**  
5. Outbox for messaging fanout  
6. Block-aware filters on both systems  
7. Badge split + app-icon / `aps.badge` policy  
8. Pref docs (which toggle hits which system)  
9. Optional later: email on Activity only  

---

## 6. Recommended production architecture (two pipelines, one APNs)

```
                    ┌─────────────────────────────┐
                    │   Shared: device_push_tokens │
                    │   APNs sendApnsAlert         │
                    └─────────────┬───────────────┘
                                  │
          ┌───────────────────────┴───────────────────────┐
          ▼                                               ▼
 ActivityNotificationService                    MessagingPushService
  • INSERT notifications                         • NO notifications row
  • Realtime Activity badge                      • Conversation/room unread only
  • Push (Activity href / badge)                 • Push (Messages/room href)
  • Future email                                 • Respect mute/block/prefs
```

### Principles
- Activity and Messaging **share tokens and APNs**, not inbox rows  
- Messaging push **must not** require an Activity insert  
- Room @mentions are Activity-first (persistent), with push  
- Mentioned users should **not** also get a generic “new room message” push for the same message  
- Idempotent Activity creators; rate-limited Messaging pushes  

---

## 7. Implementation order

See **§5 Updated implementation order**.

---

## 8. Risk assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Users miss room chat if only in Messages | Habit change | Push + unread; optional digest later |
| Legacy `room_message` Activity rows | Clutter | Hide from inbox query; optional cleanup job |
| App icon badge confusion | Support load | Document Activity vs Messages policy |
| Double push (mention + room message) | Annoyance | Mention recipients skip generic room-message push |
| Room fanout | Latency | Messaging outbox |
| Block evasion | Safety | Filter both pipelines |

---

## 9. Complexity estimates

| Feature | Complexity | Notes |
|---------|------------|-------|
| Exclude `room_message` from Activity UI/badge | **S** | Query/constant change |
| Stop inserting ordinary room_message Activity | **M** | Replace with MessagingPush |
| Room @mention Activity + push | **M** | Parse + recipient set |
| DM MessagingPush (no Activity) | **M** | |
| Badge / aps.badge split | **S–M** | |
| ActivityNotificationService wrap | **M** | |
| Block filtering | **S** | |
| Messaging outbox | **L** | |

---

## 10. Scale guidance

Same as before for Activity. For Messaging: **never** write one Activity row per room member per message; push fanout via queue; keep unread on conversation/room tables only.

---

## Preferences mapped to two systems

| Pref key | System |
|----------|--------|
| likes, comments, replies, mentions, reactions, followers, follow_requests, follow_request_accepts, story_replies, shares, achievement_*, product/maintenance/announcements | **Activity** |
| `direct_messages_enabled` | **Messaging** push |
| `room_messages_enabled` | **Messaging** push |
| `room_mentions_enabled` | **Activity** (+ push) |
| `room_joins_enabled` | **Activity** |
| Master `notifications_enabled` | Gates both (product decision) |

Schema already supports these columns — **wiring and classification**, not new columns, for the split.

---

## Edge cases (additions for split)

| Case | Handling |
|------|----------|
| Dismiss messaging push | Unread remains in Messages/Rooms; no Activity residue |
| Dismiss Activity push | Row remains unread in `/notifications` |
| Muted room | No Messaging push; product decision whether @mention overrides mute |
| User mentioned + room message prefs off | Still deliver Activity mention; push follows `room_mentions_enabled` |
| Legacy room_message Activity rows | Exclude from inbox queries |

---

## Deliverable checklist

| # | Item | Section |
|---|------|---------|
| 1 | Updated notification flow | Architecture revision + §1 |
| 2 | Updated event classification | §2 |
| 3 | Updated badge strategy | §3 |
| 4 | Updated deep-link strategy | §4 |
| 5 | Updated implementation order | §5 |

**No application functionality was implemented for this revision — document update only.**
