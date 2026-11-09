import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { tradeRoomGoLiveButtonDisabled } from "./tradeRoomGoLiveButtonDisabled.ts"

describe("tradeRoomGoLiveButtonDisabled", () => {
  it("does not disable when status API reports live for broadcaster-only prep (publicLive false)", () => {
    assert.equal(
      tradeRoomGoLiveButtonDisabled({
        isBusy: false,
        accessTokenPresent: true,
        publicLive: false,
      }),
      false
    )
  })

  it("disables when session is viewer-discoverable public", () => {
    assert.equal(
      tradeRoomGoLiveButtonDisabled({
        isBusy: false,
        accessTokenPresent: true,
        publicLive: true,
      }),
      true
    )
  })

  it("disables when busy or no token", () => {
    assert.equal(
      tradeRoomGoLiveButtonDisabled({
        isBusy: true,
        accessTokenPresent: true,
        publicLive: false,
      }),
      true
    )
    assert.equal(
      tradeRoomGoLiveButtonDisabled({
        isBusy: false,
        accessTokenPresent: false,
        publicLive: false,
      }),
      true
    )
  })
})
