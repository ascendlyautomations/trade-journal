import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  isOfficialDiscoveryTradeRoom,
  mapExploreSuggestedDiscoveryRoom,
  mergeExploreCommunityRooms,
  parseExploreSuggestedDiscoveryRoomsForViewer,
} from "./exploreCommunityTradeRoomsSelection.ts"

describe("exploreCommunityTradeRooms", () => {
  it("treats missing room_kind as community (native TradeRoomKind.parse)", () => {
    assert.equal(isOfficialDiscoveryTradeRoom({ room_kind: null }), false)
    assert.equal(isOfficialDiscoveryTradeRoom({ room_kind: "official" }), true)
    const room = mapExploreSuggestedDiscoveryRoom({
      id: "r0",
      name: "Legacy Room",
      member_count: 3,
    })
    assert.ok(room)
  })

  it("maps discovery rows including official rooms (native Explore parity)", () => {
    const room = mapExploreSuggestedDiscoveryRoom({
      id: "r-official",
      name: "Futures Lounge",
      slug: "futures-lounge",
      member_count: 120,
      room_kind: "official",
    })
    assert.ok(room)
    assert.equal(room?.memberCount, 120)
  })

  it("maps discovery rows to popular room shape", () => {
    const room = mapExploreSuggestedDiscoveryRoom({
      id: "r1",
      name: "NQ Traders",
      slug: "nq-traders",
      member_count: 12,
      room_kind: "community",
      description: "Morning session",
      image_url: "https://example.com/a.png",
    })
    assert.ok(room)
    assert.equal(room?.memberCount, 12)
    assert.equal(room?.name, "NQ Traders")
  })

  it("excludes beta hub slug and already-joined rows for viewer", () => {
    assert.equal(
      mapExploreSuggestedDiscoveryRoom({
        id: "beta",
        name: "Beta",
        slug: "tradetraxs-beta",
      }),
      null
    )
    const parsed = parseExploreSuggestedDiscoveryRoomsForViewer([
      {
        id: "r3",
        name: "Joined",
        room_kind: "community",
        is_member: true,
      },
      {
        id: "r4",
        name: "Open",
        room_kind: "community",
        is_member: false,
      },
    ])
    assert.deepEqual(parsed.map((r) => r.id), ["r4"])
  })

  it("merges pages without duplicate room ids", () => {
    const merged = mergeExploreCommunityRooms(
      [{ id: "a", name: "A", description: null, slug: null, memberCount: 1, imageUrl: null, avatarUrl: null }],
      [
        { id: "a", name: "A", description: null, slug: null, memberCount: 1, imageUrl: null, avatarUrl: null },
        { id: "b", name: "B", description: null, slug: null, memberCount: 2, imageUrl: null, avatarUrl: null },
      ]
    )
    assert.equal(merged.length, 2)
    assert.deepEqual(merged.map((r) => r.id), ["a", "b"])
  })
})
