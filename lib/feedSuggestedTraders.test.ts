import assert from "node:assert/strict"
import test from "node:test"
import {
  blockedPeerIds,
  selectSuggestedTraders,
  SUGGESTED_TRADERS_LIMIT,
  type SuggestedTrader,
} from "./feedSuggestedTraders.ts"

function trader(id: string, extra: Partial<SuggestedTrader> = {}): SuggestedTrader {
  return {
    id,
    username: id,
    name: id,
    avatar_url: null,
    is_private: false,
    ...extra,
  }
}

test("suggested traders exclude self, follows, blocks, private, and blanks", () => {
  const selected = selectSuggestedTraders(
    [
      trader("me"),
      trader("followed"),
      trader("blocked"),
      trader("private", { is_private: true }),
      trader("blank", { username: "  " }),
      trader("a"),
      trader("a"),
      trader("b"),
    ],
    {
      viewerId: "me",
      followingIds: ["followed"],
      blockedIds: ["blocked"],
      limit: 6,
    }
  )

  assert.deepEqual(
    selected.map((row) => row.id),
    ["a", "b"]
  )
})

test("suggested traders keep query order and stay bounded", () => {
  const profiles = Array.from({ length: 10 }, (_, index) =>
    trader(`t${index}`)
  )
  const selected = selectSuggestedTraders(profiles, {
    viewerId: "viewer",
    followingIds: [],
    blockedIds: [],
  })
  assert.equal(selected.length, SUGGESTED_TRADERS_LIMIT)
  assert.equal(selected[0]?.id, "t0")
  assert.equal(selected[5]?.id, "t5")
})

test("blocked peers include both directions", () => {
  assert.deepEqual(
    blockedPeerIds("me", [
      { blocker_id: "me", blocked_id: "them" },
      { blocker_id: "other", blocked_id: "me" },
      { blocker_id: "x", blocked_id: "y" },
    ]),
    ["them", "other"]
  )
})
