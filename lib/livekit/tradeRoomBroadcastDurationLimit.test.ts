import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  broadcastDurationWarningLevel,
  computeBroadcastExpiresAt,
  formatBroadcastCountdown,
  isBroadcastPastExpiresAt,
  liveKitTokenTtlCapSeconds,
} from "./tradeRoomBroadcastDurationLimit.ts"

describe("tradeRoomBroadcastDurationLimit", () => {
  it("computes expires_at two hours ahead", () => {
    const base = Date.parse("2026-01-01T12:00:00.000Z")
    const expires = computeBroadcastExpiresAt(base)
    assert.equal(expires, "2026-01-01T14:00:00.000Z")
  })

  it("caps LiveKit token TTL to session remainder", () => {
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString()
    const ttl = liveKitTokenTtlCapSeconds(expiresAt, 900)
    assert.ok(ttl <= 600)
    assert.ok(ttl >= 60)
  })

  it("flags warning thresholds", () => {
    assert.equal(broadcastDurationWarningLevel(14 * 60 * 1000), "15m")
    assert.equal(broadcastDurationWarningLevel(4 * 60 * 1000), "5m")
    assert.equal(broadcastDurationWarningLevel(0), "expired")
  })

  it("formats countdown", () => {
    assert.equal(formatBroadcastCountdown(125_000), "2:05")
    assert.equal(formatBroadcastCountdown(3_661_000), "1:01:01")
  })

  it("detects past expiry", () => {
    const past = new Date(Date.now() - 1000).toISOString()
    assert.equal(isBroadcastPastExpiresAt(past), true)
    assert.equal(isBroadcastPastExpiresAt(null), false)
  })
})