import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { classifyViewerBroadcastDisconnect } from "./tradeRoomBroadcastViewerDisconnect.ts"

describe("classifyViewerBroadcastDisconnect", () => {
  const session = "sess-obs-1"
  const viewer = "viewer-uuid"

  it("normal broadcast end → stream_ended", () => {
    assert.deepEqual(
      classifyViewerBroadcastDisconnect({
        watchingSessionId: session,
        statusLive: false,
        statusSessionId: null,
        snapshot: null,
        viewerUserId: viewer,
      }),
      { type: "stream_ended" }
    )
  })

  it("OBS host shutdown (session row ended) → stream_ended", () => {
    assert.deepEqual(
      classifyViewerBroadcastDisconnect({
        watchingSessionId: session,
        statusLive: false,
        statusSessionId: session,
        snapshot: null,
        viewerUserId: viewer,
      }),
      { type: "stream_ended" }
    )
  })

  it("session superseded → stream_ended", () => {
    assert.deepEqual(
      classifyViewerBroadcastDisconnect({
        watchingSessionId: session,
        statusLive: true,
        statusSessionId: "other-session",
        snapshot: {
          sessionId: "other-session",
          presentInLiveKitBroadcastRoom: true,
        },
        viewerUserId: viewer,
      }),
      { type: "stream_ended" }
    )
  })

  it("moderator removal (still live, not in room) → removed", () => {
    assert.deepEqual(
      classifyViewerBroadcastDisconnect({
        watchingSessionId: session,
        statusLive: true,
        statusSessionId: session,
        snapshot: {
          sessionId: session,
          presentInLiveKitBroadcastRoom: false,
        },
        viewerUserId: viewer,
      }),
      { type: "removed", blocked: false }
    )
  })

  it("moderator block → removed blocked", () => {
    assert.deepEqual(
      classifyViewerBroadcastDisconnect({
        watchingSessionId: session,
        statusLive: true,
        statusSessionId: session,
        snapshot: {
          sessionId: session,
          blockedFromBroadcastRejoin: true,
          presentInLiveKitBroadcastRoom: false,
        },
        viewerUserId: viewer,
      }),
      { type: "removed", blocked: true }
    )
  })

  it("network drop while still in room → connection_lost", () => {
    assert.deepEqual(
      classifyViewerBroadcastDisconnect({
        watchingSessionId: session,
        statusLive: true,
        statusSessionId: session,
        snapshot: {
          sessionId: session,
          presentInLiveKitBroadcastRoom: true,
        },
        viewerUserId: viewer,
      }),
      { type: "connection_lost" }
    )
  })
})
