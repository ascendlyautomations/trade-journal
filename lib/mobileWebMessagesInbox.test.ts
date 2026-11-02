import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  conversationMatchesMobileWebInboxSearch,
  mobileWebInboxHasVisibleRows,
  mobileWebInboxTradeRoomHref,
  MOBILE_WEB_MESSAGES_INBOX_PREVIEW_LIMIT,
  normalizeMobileWebInboxTradeRoom,
  sliceMobileWebInboxPreview,
  splitMobileWebMessagesInbox,
} from "./mobileWebMessagesInbox.ts"

const dm = (id: string, extra: Record<string, unknown> = {}) => ({
  id,
  is_group: false,
  is_pinned: false,
  name: null,
  displayName: `Trader ${id}`,
  username: `user_${id}`,
  ...extra,
})

describe("normalizeMobileWebInboxTradeRoom", () => {
  it("keeps slug, owner, and image from cached room rows", () => {
    const room = normalizeMobileWebInboxTradeRoom({
      id: "room-1",
      name: "NQ Desk",
      slug: "nq-desk",
      owner_user_id: "owner-1",
      avatar_url: "https://cdn.example/a.png",
      is_private: true,
    })
    assert.equal(room?.id, "room-1")
    assert.equal(room?.slug, "nq-desk")
    assert.equal(room?.owner_user_id, "owner-1")
    assert.equal(room?.image_url, "https://cdn.example/a.png")
    assert.equal(room?.is_private, true)
    assert.equal(mobileWebInboxTradeRoomHref(room!), "/community?room=nq-desk")
  })

  it("falls back to id in the community href when slug is missing", () => {
    const room = normalizeMobileWebInboxTradeRoom({ id: "abc", name: "Desk" })
    assert.equal(mobileWebInboxTradeRoomHref(room!), "/community?room=abc")
  })
})

describe("splitMobileWebMessagesInbox", () => {
  it("splits pinned DMs, unpinned DMs, owned room, and joined rooms", () => {
    const split = splitMobileWebMessagesInbox({
      conversations: [
        dm("p1", { is_pinned: true, displayName: "Pinned" }),
        dm("d1", { displayName: "Alex" }),
        dm("d2", { is_group: true, name: "Desk Chat", displayName: "Desk Chat" }),
      ],
      rooms: [
        {
          id: "mine",
          name: "My Room",
          owner_user_id: "me",
        },
        { id: "joined", name: "NQ Morning" },
      ],
      viewerId: "me",
    })

    assert.deepEqual(
      split.pinned.map((row) => row.id),
      ["p1"]
    )
    assert.deepEqual(
      split.directMessages.map((row) => row.id),
      ["d1", "d2"]
    )
    assert.equal(split.ownedRoom?.id, "mine")
    assert.deepEqual(
      split.joinedRooms.map((row) => row.id),
      ["joined"]
    )
  })

  it("filters conversations and rooms by the same search query", () => {
    const split = splitMobileWebMessagesInbox({
      conversations: [
        dm("1", { displayName: "Alex", username: "alex" }),
        dm("2", { displayName: "Jordan", username: "jordan" }),
      ],
      rooms: [
        { id: "nq", name: "NQ Morning" },
        { id: "es", name: "ES Review" },
      ],
      viewerId: "me",
      search: "nq",
    })
    assert.equal(split.directMessages.length, 0)
    assert.equal(split.joinedRooms.length, 1)
    assert.equal(split.joinedRooms[0].id, "nq")
    assert.equal(
      conversationMatchesMobileWebInboxSearch(
        dm("1", { displayName: "Alex", username: "alex" }),
        "alex"
      ),
      true
    )
  })
})

describe("sliceMobileWebInboxPreview", () => {
  it("shows four rows until expanded", () => {
    const ids = ["a", "b", "c", "d", "e", "f"]
    assert.deepEqual(sliceMobileWebInboxPreview(ids, false), ["a", "b", "c", "d"])
    assert.equal(
      sliceMobileWebInboxPreview(ids, false).length,
      MOBILE_WEB_MESSAGES_INBOX_PREVIEW_LIMIT
    )
    assert.deepEqual(sliceMobileWebInboxPreview(ids, true), ids)
  })
})

describe("mobileWebInboxHasVisibleRows", () => {
  it("is empty only when every section is empty", () => {
    assert.equal(
      mobileWebInboxHasVisibleRows({
        pinned: [],
        directMessages: [],
        ownedRoom: null,
        joinedRooms: [],
      }),
      false
    )
    assert.equal(
      mobileWebInboxHasVisibleRows({
        pinned: [],
        directMessages: [],
        ownedRoom: { id: "mine" },
        joinedRooms: [],
      }),
      true
    )
  })
})
