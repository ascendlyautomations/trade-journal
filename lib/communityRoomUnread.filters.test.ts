import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { describe, it } from "node:test"
import {
  roomIdFromRoomMessageInsert,
  roomUnreadMessageFilters,
} from "./communityRoomUnreadLogic.ts"
import { REALTIME_IN_FILTER_MAX_IDS, stableIdKey } from "./realtimeFilters.ts"

function idsInFilter(filter: string): string[] {
  assert.match(filter, /^room_id=in\.\(.+\)$/)
  return filter.slice("room_id=in.(".length, -1).split(",")
}

function roomIds(count: number): string[] {
  return Array.from({ length: count }, (_, index) =>
    `room-${String(index).padStart(3, "0")}`
  )
}

describe("room unread message filters", () => {
  it("creates no room_messages filter for an empty room list", () => {
    assert.deepEqual(roomUnreadMessageFilters([]), [])
    assert.deepEqual(roomUnreadMessageFilters(["", "  "]), [])
  })

  it("uses one filtered binding for a single room", () => {
    assert.deepEqual(roomUnreadMessageFilters(["room-a"]), [
      "room_id=in.(room-a)",
    ])
  })

  it("uses one filtered binding for multiple rooms under the chunk limit", () => {
    for (const count of [5, 20, 50]) {
      const filters = roomUnreadMessageFilters(roomIds(count))
      assert.equal(filters.length, 1)
      assert.equal(idsInFilter(filters[0]!).length, count)
    }
  })

  it("keeps exactly the chunk limit in one binding and splits the next id", () => {
    const atLimit = roomUnreadMessageFilters(
      roomIds(REALTIME_IN_FILTER_MAX_IDS)
    )
    assert.equal(atLimit.length, 1)
    assert.equal(idsInFilter(atLimit[0]!).length, REALTIME_IN_FILTER_MAX_IDS)

    const over = roomUnreadMessageFilters(
      roomIds(REALTIME_IN_FILTER_MAX_IDS + 1)
    )
    assert.equal(over.length, 2)
    assert.equal(idsInFilter(over[0]!).length, REALTIME_IN_FILTER_MAX_IDS)
    assert.equal(idsInFilter(over[1]!).length, 1)
  })

  it("chunks 250 rooms into three filtered bindings", () => {
    const filters = roomUnreadMessageFilters(roomIds(250))
    assert.equal(filters.length, 3)
    const covered = filters.flatMap(idsInFilter)
    assert.equal(covered.length, 250)
    assert.equal(new Set(covered).size, 250)
  })

  it("drops duplicate ids and ignores room order", () => {
    assert.deepEqual(
      roomUnreadMessageFilters(["b", "a", "b", "a"]),
      ["room_id=in.(a,b)"]
    )
    assert.deepEqual(
      roomUnreadMessageFilters(["z", "m", "a"]),
      roomUnreadMessageFilters(["a", "z", "m"])
    )
    assert.equal(stableIdKey(["z", "m", "a"]), stableIdKey(["a", "z", "m"]))
  })

  it("never emits an unfiltered or per-room eq subscription", () => {
    const filters = roomUnreadMessageFilters(roomIds(250))
    for (const filter of filters) {
      assert.match(filter, /^room_id=in\.\(.+\)$/)
      assert.equal(filter.includes("room_id=eq."), false)
      assert.ok(idsInFilter(filter).length <= REALTIME_IN_FILTER_MAX_IDS)
    }
  })

  it("reads room_id from the inserted row", () => {
    assert.equal(
      roomIdFromRoomMessageInsert({ room_id: " room-a ", user_id: "u1" }),
      "room-a"
    )
    assert.equal(roomIdFromRoomMessageInsert({ user_id: "u1" }), "")
    assert.equal(roomIdFromRoomMessageInsert(null), "")
  })
})

describe("room unread subscription source", () => {
  it("attaches only chunked room filters and leaves shared notifications in place", () => {
    const src = readFileSync(
      new URL("./communityRoomUnread.ts", import.meta.url),
      "utf8"
    )
    assert.match(src, /roomUnreadMessageFilters/)
    assert.match(src, /filter: roomFilter/)
    assert.match(src, /subscribeNotificationChanges/)
    assert.doesNotMatch(src, /room_id=eq\./)
    assert.doesNotMatch(src, /setInterval/)
  })
})
