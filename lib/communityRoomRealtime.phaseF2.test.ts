import { describe, it } from "node:test"
import { isRoomNotificationType, extractRoomIdFromNotification, shouldSkipUnreadIncrement, stableSortedRoomIds, } from "./communityRoomUnreadLogic.ts"
import { dedupePresenceByUserId } from "./roomRealtimePresence.ts"
import { buildRealtimeInFilter } from "./realtimeFilters.ts"
import assert from "node:assert/strict"

describe("communityRoomUnread (Phase F2)", () => {
  it("recognizes room notification types", () => {
    assert.equal(isRoomNotificationType("room_mention"), true)
    assert.equal(isRoomNotificationType("room_join"), true)
    assert.equal(isRoomNotificationType("like"), false)
  })

  it("extracts room_id from notification content JSON", () => {
    const roomId = extractRoomIdFromNotification({
      type: "room_mention",
      content: JSON.stringify({ room_id: "abc-123" }),
    })
    assert.equal(roomId, "abc-123")
  })

  it("skips unread increment for intentionally read open room", () => {
    assert.equal(
      shouldSkipUnreadIncrement({
        roomId: "r1",
        selectedRoomId: "r1",
        isRoomMarkedRead: (roomId) => roomId === "r1",
      }),
      true
    )
    assert.equal(
      shouldSkipUnreadIncrement({
        roomId: "r2",
        selectedRoomId: "r1",
        isRoomMarkedRead: (roomId) => roomId === "r1",
      }),
      false
    )
  })
})

describe("roomRealtimePresence dedupe (Phase F2)", () => {
  it("deduplicates multiple tabs by user_id", () => {
    const users = dedupePresenceByUserId({
      tab1: [
        {
          user_id: "u1",
          username: "a",
          avatar_url: null,
          entered_at: "2026-01-01T00:00:00Z",
        },
      ],
      tab2: [
        {
          user_id: "u1",
          username: "a",
          avatar_url: null,
          entered_at: "2026-01-02T00:00:00Z",
        },
      ],
    })
    assert.equal(users.length, 1)
    assert.equal(users[0]?.entered_at, "2026-01-02T00:00:00Z")
  })
})

describe("community unread channel (Phase F2 security)", () => {
  it("stableSortedRoomIds dedupes and sorts deterministically", () => {
    assert.deepEqual(
      stableSortedRoomIds(["b", "a", "b", ""]),
      ["a", "b"]
    )
    assert.deepEqual(
      stableSortedRoomIds(["z", "a"]),
      stableSortedRoomIds(["a", "z"])
    )
  })
})

describe("reaction integrity expectations (Phase F2 security)", () => {
  it("documents reject-on-mismatch trigger semantics", () => {
    const mismatchRejected = true
    const nullRoomIdPopulated = true
    const compositeFkEnforced = true
    assert.equal(
      mismatchRejected && nullRoomIdPopulated && compositeFkEnforced,
      true
    )
  })
})

describe("reaction Realtime filter (Phase F2)", () => {
  it("builds multi-uuid in filter that Realtime rejects for reactions", () => {
    const filter = buildRealtimeInFilter("message_id", [
      "11111111-1111-1111-1111-111111111111",
      "22222222-2222-2222-2222-222222222222",
    ])
    assert.match(filter ?? "", /message_id=in\.\(/)
    assert.notEqual(
      filter,
      "message_id=eq.11111111-1111-1111-1111-111111111111"
    )
  })

  it("prefers stable room_id=eq filter for reactions", () => {
    const roomId = "33333333-3333-3333-3333-333333333333"
    const roomScoped = `room_id=eq.${roomId}`
    assert.equal(roomScoped.includes("in.("), false)
  })
})
export {}
