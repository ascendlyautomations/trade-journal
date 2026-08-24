import { describe, it } from "node:test"
import { ROOM_MESSAGE_REACTIONS_EMBED, ROOM_MESSAGE_REACTIONS_FKEY, ROOM_MESSAGE_SELECT_SHAPE, ROOM_MESSAGE_SELECT_COMPACT, } from "./roomMessageSelect.ts"
import assert from "node:assert/strict"

describe("roomMessageSelect (PGRST201 embed)", () => {
  it("uses explicit composite FK hint for reactions", () => {
    assert.equal(
      ROOM_MESSAGE_REACTIONS_EMBED,
      "room_message_reactions!room_message_reactions_message_room_fkey"
    )
    assert.match(
      ROOM_MESSAGE_SELECT_SHAPE,
      /room_message_reactions!room_message_reactions_message_room_fkey/
    )
    assert.match(
      ROOM_MESSAGE_SELECT_COMPACT,
      /room_message_reactions!room_message_reactions_message_room_fkey/
    )
  })

  it("does not use ambiguous bare room_message_reactions embed", () => {
    assert.doesNotMatch(ROOM_MESSAGE_SELECT_SHAPE, /\n  room_message_reactions \(/)
  })

  it("preserves trade FK disambiguation", () => {
    assert.match(ROOM_MESSAGE_SELECT_SHAPE, /trades!room_messages_trade_id_fkey/)
  })

  it("exports stable FKEY name for migrations", () => {
    assert.equal(
      ROOM_MESSAGE_REACTIONS_FKEY,
      "room_message_reactions_message_room_fkey"
    )
  })
})
export {}
