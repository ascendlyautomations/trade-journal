import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { broadcastModerationActionAllowed } from "./broadcastModerationAccess.ts"

describe("broadcastModerationActionAllowed", () => {
  it("allows broadcaster all actions", () => {
    for (const action of [
      "invite_speak",
      "mute_speaker",
      "remove_viewer",
      "dismiss_hand",
    ] as const) {
      assert.equal(
        broadcastModerationActionAllowed({
          action,
          isBroadcaster: true,
          canModerate: false,
          canManage: false,
        }),
        true
      )
    }
  })

  it("delegates mute/remove/dismiss to room moderators only", () => {
    assert.equal(
      broadcastModerationActionAllowed({
        action: "mute_speaker",
        isBroadcaster: false,
        canModerate: true,
        canManage: false,
      }),
      true
    )
    assert.equal(
      broadcastModerationActionAllowed({
        action: "invite_speak",
        isBroadcaster: false,
        canModerate: true,
        canManage: false,
      }),
      false
    )
  })
})
