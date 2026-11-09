import assert from "node:assert/strict"
import { test } from "node:test"
import { buildTradeRoomBroadcastLiveNotifyContent } from "@/lib/livekit/tradeRoomBroadcastLiveNotifyContent.ts"
import { buildPushDeepLinkHref } from "@/lib/server/push/pushCopy.ts"

test("room_live push content carries uuid slug and session for routing", () => {
  const content = buildTradeRoomBroadcastLiveNotifyContent({
    roomId: "11111111-1111-1111-1111-111111111111",
    roomSlug: "momentum",
    roomName: "Momentum",
    broadcastSessionId: "sess-abc",
  })
  const parsed = JSON.parse(
    JSON.stringify(content)
  ) as typeof content
  assert.equal(parsed.room_id, "11111111-1111-1111-1111-111111111111")
  assert.equal(parsed.room_slug, "momentum")
  assert.equal(parsed.broadcast_session_id, "sess-abc")

  const href = buildPushDeepLinkHref({
    type: "room_live",
    recipientUserId: "user-1",
    room_id: parsed.room_id,
    content: JSON.stringify(parsed),
  })
  assert.match(href, /live=1/)
  assert.match(href, /room=momentum/)
})
