import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { describe, it } from "node:test"
import {
  BROADCAST_DISCONNECT_CRON_MAX_LAG_MS,
  BROADCAST_DISCONNECT_GRACE_MS,
  decideBroadcasterDisconnectCheck,
  isStaleLiveKitBroadcastWebhookEvent,
} from "./tradeRoomBroadcastDisconnectCheck.ts"

describe("tradeRoomBroadcastDisconnectCheck — stale LiveKit webhooks", () => {
  it("ignores participant_left events that predate the active session", () => {
    const startedAt = "2026-11-06T02:00:00.000Z"
    const eventSeconds = Math.floor(
      new Date("2026-11-06T01:59:00.000Z").getTime() / 1000
    )
    assert.equal(
      isStaleLiveKitBroadcastWebhookEvent(eventSeconds, startedAt),
      true
    )
  })

  it("accepts events after the session started", () => {
    const startedAt = "2026-11-06T02:00:00.000Z"
    const eventSeconds = Math.floor(
      new Date("2026-11-06T02:00:05.000Z").getTime() / 1000
    )
    assert.equal(
      isStaleLiveKitBroadcastWebhookEvent(eventSeconds, startedAt),
      false
    )
  })
})

describe("tradeRoomBroadcastDisconnectCheck — decision logic", () => {
  const nowMs = Date.parse("2026-11-06T02:00:10.000Z")
  const dueCheckAtMs = Date.parse("2026-11-06T02:00:01.000Z")
  const futureCheckAtMs = Date.parse("2026-11-06T02:00:20.000Z")

  it("waits until grace timestamp (delayed cleanup / serverless restart path)", () => {
    const decision = decideBroadcasterDisconnectCheck({
      nowMs,
      checkAtMs: futureCheckAtMs,
      rowSessionId: "sess-a",
      activeSessionId: "sess-a",
      broadcasterConnected: false,
      pendingReason: "livekit_left",
    })
    assert.deepEqual(decision, { action: "wait" })
  })

  it("clears when a newer session replaced the row (stale disconnect event)", () => {
    const decision = decideBroadcasterDisconnectCheck({
      nowMs,
      checkAtMs: dueCheckAtMs,
      rowSessionId: "sess-old",
      activeSessionId: "sess-new",
      broadcasterConnected: false,
      pendingReason: "livekit_left",
    })
    assert.deepEqual(decision, { action: "clear", reason: "stale_session" })
  })

  it("clears without ending when the broadcaster reconnected", () => {
    const decision = decideBroadcasterDisconnectCheck({
      nowMs,
      checkAtMs: dueCheckAtMs,
      rowSessionId: "sess-a",
      activeSessionId: "sess-a",
      broadcasterConnected: true,
      pendingReason: "livekit_left",
    })
    assert.deepEqual(decision, { action: "clear", reason: "reconnected" })
  })

  it("ends when grace elapsed, session matches, and broadcaster is absent", () => {
    const decision = decideBroadcasterDisconnectCheck({
      nowMs,
      checkAtMs: dueCheckAtMs,
      rowSessionId: "sess-a",
      activeSessionId: "sess-a",
      broadcasterConnected: false,
      pendingReason: "livekit_left",
    })
    assert.deepEqual(decision, {
      action: "end",
      reason: "livekit_left",
    })
  })

  it("duplicate disconnect signals extend grace by rescheduling check_at in DB", () => {
    assert.ok(BROADCAST_DISCONNECT_GRACE_MS >= 8_000)
    const firstDue = nowMs - 1_000
    const extendedDue = nowMs + BROADCAST_DISCONNECT_GRACE_MS - 1_000
    assert.equal(
      decideBroadcasterDisconnectCheck({
        nowMs,
        checkAtMs: firstDue,
        rowSessionId: "sess-a",
        activeSessionId: "sess-a",
        broadcasterConnected: false,
        pendingReason: "livekit_left",
      }).action,
      "end"
    )
    assert.equal(
      decideBroadcasterDisconnectCheck({
        nowMs,
        checkAtMs: extendedDue,
        rowSessionId: "sess-a",
        activeSessionId: "sess-a",
        broadcasterConnected: false,
        pendingReason: "livekit_left",
      }).action,
      "wait"
    )
  })
})

describe("tradeRoom broadcast disconnect migration contract", () => {
  const sql = readFileSync(
    "supabase/migrations/20261107010000_trade_room_broadcast_disconnect_check.sql",
    "utf8"
  )

  it("stores durable disconnect check timestamps on room_live_broadcasts", () => {
    assert.match(sql, /broadcaster_disconnect_check_at/)
    assert.match(sql, /room_live_broadcasts_disconnect_check_due_idx/)
  })

  it("schedules pg_cron to invoke the BFF processor (no in-memory grace)", () => {
    assert.match(sql, /livekit-broadcast-disconnect-check/)
    assert.match(sql, /process-broadcast-disconnect/)
    assert.match(sql, /pg_cron/)
  })

  it("documents cron lag bound for production guarantees", () => {
    assert.ok(BROADCAST_DISCONNECT_CRON_MAX_LAG_MS === 60_000)
  })
})
