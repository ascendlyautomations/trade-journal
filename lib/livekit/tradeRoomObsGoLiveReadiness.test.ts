import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { tradeRoomObsGoLiveToRoomEnabled } from "./tradeRoomObsGoLiveReadiness.ts"

describe("tradeRoomObsGoLiveToRoomEnabled", () => {
  it("disabled when not in OBS prep", () => {
    assert.equal(
      tradeRoomObsGoLiveToRoomEnabled({
        obsPreparingHost: false,
        isBusy: false,
        primaryMediaPublisherConnected: true,
      }),
      false
    )
  })

  it("disabled when busy", () => {
    assert.equal(
      tradeRoomObsGoLiveToRoomEnabled({
        obsPreparingHost: true,
        isBusy: true,
        primaryMediaPublisherConnected: true,
      }),
      false
    )
  })

  it("disabled when primary publisher not connected / no video published (server)", () => {
    assert.equal(
      tradeRoomObsGoLiveToRoomEnabled({
        obsPreparingHost: true,
        isBusy: false,
        primaryMediaPublisherConnected: false,
      }),
      false
    )
    assert.equal(
      tradeRoomObsGoLiveToRoomEnabled({
        obsPreparingHost: true,
        isBusy: false,
        primaryMediaPublisherConnected: undefined,
      }),
      false
    )
  })

  it("enabled when prep host and server reports program video", () => {
    assert.equal(
      tradeRoomObsGoLiveToRoomEnabled({
        obsPreparingHost: true,
        isBusy: false,
        primaryMediaPublisherConnected: true,
      }),
      true
    )
  })
})
