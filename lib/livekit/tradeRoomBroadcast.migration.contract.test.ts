import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { describe, it } from "node:test"

const baseSql = readFileSync(
  "supabase/migrations/20261105193000_trade_room_live_broadcast.sql",
  "utf8"
)
const voiceModeSql = readFileSync(
  "supabase/migrations/20261105210000_trade_room_broadcast_voice_mode.sql",
  "utf8"
)
const obsIngressSql = readFileSync(
  "supabase/migrations/20261107160000_trade_room_broadcast_obs_ingress.sql",
  "utf8"
)
const videoObsSql = readFileSync(
  "supabase/migrations/20261107180000_trade_room_broadcast_video_source_obs.sql",
  "utf8"
)
const visibilitySql = readFileSync(
  "supabase/migrations/20261107190000_trade_room_broadcast_visibility.sql",
  "utf8"
)
const streamTitleSql = readFileSync(
  "supabase/migrations/20261113230000_room_live_broadcast_stream_title.sql",
  "utf8"
)
const durationLimitSql = readFileSync(
  "supabase/migrations/20261123194500_trade_room_broadcast_duration_limit.sql",
  "utf8"
)
const ingressLeaseSql = readFileSync(
  "supabase/migrations/20261124240000_trade_room_broadcast_ingress_lease.sql",
  "utf8"
)
const broadcastChatTradeSharesSql = readFileSync(
  "supabase/migrations/20261125020000_broadcast_chat_trade_shares.sql",
  "utf8"
)

describe("Trade Room live broadcast migration contract", () => {
  it("defines room_live_broadcasts with one active row per room", () => {
    assert.match(baseSql, /room_live_broadcasts/)
    assert.match(baseSql, /room_live_broadcasts_one_active_per_room_idx/)
    assert.match(baseSql, /enable row level security/)
    assert.match(baseSql, /ended_at is null/)
  })

  it("adds voice_mode and video_source session metadata", () => {
    assert.match(voiceModeSql, /voice_mode/)
    assert.match(voiceModeSql, /broadcast_only/)
    assert.match(voiceModeSql, /open_voice/)
    assert.match(voiceModeSql, /video_source/)
  })

  it("adds OBS / LiveKit Ingress metadata columns (no stored stream keys)", () => {
    assert.match(obsIngressSql, /broadcast_source/)
    assert.match(obsIngressSql, /primary_media_publisher_identity/)
    assert.match(obsIngressSql, /livekit_ingress_id/)
    assert.match(obsIngressSql, /ingress_status_snapshot/)
  })

  it("allows video_source obs for OBS-only sessions", () => {
    assert.match(videoObsSql, /video_source/)
    assert.match(videoObsSql, /'obs'/)
  })

  it("adds visibility and go_live_notified_at for OBS preparation", () => {
    assert.match(visibilitySql, /visibility/)
    assert.match(visibilitySql, /preparing/)
    assert.match(visibilitySql, /go_live_notified_at/)
  })

  it("adds stream_title with length check", () => {
    assert.match(streamTitleSql, /stream_title/)
    assert.match(streamTitleSql, /<= 100/)
  })

  it("adds video broadcast expires_at and cross-room broadcaster cooldown", () => {
    assert.match(durationLimitSql, /expires_at/)
    assert.match(durationLimitSql, /room_live_broadcast_broadcaster_cooldowns/)
    assert.match(durationLimitSql, /room_live_broadcasts_duration_expired_due_idx/)
  })

  it("adds cross-instance OBS ingress creation lease RPCs", () => {
    assert.match(ingressLeaseSql, /ingress_creation_lease_token/)
    assert.match(ingressLeaseSql, /trade_room_broadcast_claim_ingress_lease/)
    assert.match(ingressLeaseSql, /trade_room_broadcast_commit_ingress/)
    assert.match(ingressLeaseSql, /for update/)
  })

  it("adds livestream chat trade share grants without publishing trades", () => {
    assert.match(broadcastChatTradeSharesSql, /room_live_broadcast_chat_trade_shares/)
    assert.match(broadcastChatTradeSharesSql, /trades_select_shared_in_broadcast_chat/)
    assert.match(broadcastChatTradeSharesSql, /rpc_v1_broadcast_chat_register_trade_share/)
    assert.match(broadcastChatTradeSharesSql, /trades\.is_public/)
  })
})
