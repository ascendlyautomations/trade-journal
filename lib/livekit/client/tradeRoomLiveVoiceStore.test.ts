import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { createExternalStoreSnapshotCache } from "./externalStoreSnapshot.ts"

describe("tradeRoomLiveVoiceStore — useSyncExternalStore snapshots", () => {
  it("returns the same snapshot reference until publish", () => {
    let version = 0
    const cache = createExternalStoreSnapshotCache(() => ({ version }))
    const first = cache.getSnapshot()
    const second = cache.getSnapshot()
    assert.equal(first, second)

    version = 1
    cache.publish(() => ({ version }))
    const third = cache.getSnapshot()
    assert.notEqual(first, third)
    assert.equal(third.version, 1)
  })
})
