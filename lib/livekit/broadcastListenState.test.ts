import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  broadcastElementListen,
  defaultBroadcastListenState,
  mediaElementVolumeIsAdjustable,
  replaceAttachedAudioSlot,
  withBroadcastListenMuted,
  withBroadcastListenVolume,
} from "./broadcastListenState.ts"

describe("broadcast listen state", () => {
  it("keeps the previous level when muted and applies it to a later track", () => {
    const remembered = withBroadcastListenVolume(defaultBroadcastListenState(), 0.35)
    const muted = withBroadcastListenMuted(remembered, true)
    assert.deepEqual(broadcastElementListen(muted), { muted: true, volume: 0.35 })
    const restored = withBroadcastListenMuted(muted, false)
    assert.deepEqual(broadcastElementListen(restored), { muted: false, volume: 0.35 })
  })

  it("removes the previous element before storing a replacement for the same track", () => {
    const attached = new Map<string, string>()
    const removed: string[] = []
    replaceAttachedAudioSlot(attached, "track-1", "first", (previous) => {
      removed.push(previous)
    })
    replaceAttachedAudioSlot(attached, "track-1", "second", (previous) => {
      removed.push(previous)
    })
    assert.deepEqual(removed, ["first"])
    assert.equal(attached.size, 1)
    assert.equal(attached.get("track-1"), "second")
  })

  it("detects browsers that ignore media element volume", () => {
    assert.equal(mediaElementVolumeIsAdjustable({ volume: 1 }), true)
    const locked = {
      _volume: 1,
      get volume() {
        return this._volume
      },
      set volume(value: number) {
        if (value === 1) this._volume = 1
      },
    }
    assert.equal(mediaElementVolumeIsAdjustable(locked), false)
  })
})
