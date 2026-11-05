import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  audioConsumerMayStart,
  consumersPreemptedByLiveVoice,
} from "../audio/tradeTraxsAudioPolicy.ts"
import { readLiveKitServerConfig } from "./config.ts"
import { isLiveKitOutboxProcessorAuthorized } from "./outboxProcessorAuth.ts"
import {
  liveKitRoomName,
  parseLiveKitRoomName,
} from "./liveKitRoomName.ts"

describe("LiveKit Phase 0 — room naming", () => {
  it("builds stable tt/{room}/{section} names", () => {
    const roomId = "11111111-1111-1111-1111-111111111111"
    const sectionId = "22222222-2222-2222-2222-222222222222"
    const name = liveKitRoomName(roomId, sectionId)
    assert.equal(name, `tt/${roomId}/${sectionId}`)
    assert.deepEqual(parseLiveKitRoomName(name), {
      roomId,
      sectionId,
    })
  })

  it("rejects malformed room names", () => {
    assert.equal(parseLiveKitRoomName("general"), null)
    assert.equal(parseLiveKitRoomName("tt-only"), null)
  })
})

describe("LiveKit Phase 0 — audio policy", () => {
  it("live voice preempts voice notes and feed video", () => {
    assert.deepEqual(consumersPreemptedByLiveVoice(), [
      "voice_note_record",
      "voice_note_playback",
      "feed_video",
    ])
    assert.equal(
      audioConsumerMayStart("livekit_voice", "feed_video"),
      true
    )
    assert.equal(
      audioConsumerMayStart("feed_video", "livekit_voice"),
      false
    )
  })
})

describe("LiveKit outbox processor auth", () => {
  it("rejects missing or wrong bearer secret", () => {
    const prev =
      process.env.LIVEKIT_OUTBOX_WEBHOOK_SECRET ??
      process.env.CRON_SECRET
    delete process.env.LIVEKIT_OUTBOX_WEBHOOK_SECRET
    delete process.env.CRON_SECRET
    const req = new Request("http://localhost/api/internal/livekit/process-outbox")
    assert.equal(isLiveKitOutboxProcessorAuthorized(req), false)

    process.env.LIVEKIT_OUTBOX_WEBHOOK_SECRET = "test-secret-xyz"
    const authed = new Request("http://localhost/api/internal/livekit/process-outbox", {
      headers: { Authorization: "Bearer test-secret-xyz" },
    })
    assert.equal(isLiveKitOutboxProcessorAuthorized(authed), true)

    if (prev !== undefined) {
      process.env.LIVEKIT_OUTBOX_WEBHOOK_SECRET = prev
    } else {
      delete process.env.LIVEKIT_OUTBOX_WEBHOOK_SECRET
    }
  })
})

describe("LiveKit Phase 0 — config", () => {
  it("returns null when env is incomplete", () => {
    const prevUrl = process.env.LIVEKIT_URL
    const prevKey = process.env.LIVEKIT_API_KEY
    const prevSecret = process.env.LIVEKIT_API_SECRET
    delete process.env.LIVEKIT_URL
    delete process.env.LIVEKIT_API_KEY
    delete process.env.LIVEKIT_API_SECRET
    assert.equal(readLiveKitServerConfig(), null)
    if (prevUrl !== undefined) process.env.LIVEKIT_URL = prevUrl
    if (prevKey !== undefined) process.env.LIVEKIT_API_KEY = prevKey
    if (prevSecret !== undefined) process.env.LIVEKIT_API_SECRET = prevSecret
  })
})
