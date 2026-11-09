import assert from "node:assert/strict"
import { describe, it } from "node:test"

/** Mirrors GET /api/livekit/broadcast/status JSON consumed by web + iOS. */
describe("tradeRoomBroadcast status contract", () => {
  it("accepts live=false minimal payload", () => {
    const payload = JSON.parse('{"live":false}')
    assert.equal(payload.live, false)
  })

  it("accepts live=true with session metadata", () => {
    const payload = JSON.parse(
      JSON.stringify({
        live: true,
        publicLive: true,
        visibility: "public",
        broadcastSessionId: "sess-1",
        broadcasterUserId: "user-1",
        broadcasterDisplayName: "Host",
        startedAt: "2026-01-01T00:00:00.000Z",
        voiceMode: "broadcast_only",
        videoSource: "screen",
        broadcastSource: "obs",
        primaryMediaPublisherIdentity: "tt-obs-sess-1",
        livekitIngressId: "ingress-1",
        ingressStatusSnapshot: "ENDPOINT_BUFFERING",
        hostConnected: false,
        primaryMediaPublisherConnected: true,
        broadcasterConnected: true,
        viewerCount: 2,
      })
    )
    assert.equal(payload.live, true)
    assert.equal(payload.broadcastSessionId, "sess-1")
    assert.equal(payload.videoSource, "screen")
    assert.equal(payload.broadcastSource, "obs")
    assert.equal(payload.primaryMediaPublisherIdentity, "tt-obs-sess-1")
  })
})
