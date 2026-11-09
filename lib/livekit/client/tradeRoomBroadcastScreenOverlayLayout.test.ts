import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  screenOverlayPipRect,
  screenOverlayPipSize,
} from "./tradeRoomBroadcastScreenOverlayLayout.ts"

describe("tradeRoomBroadcastScreenOverlayLayout", () => {
  it("defaults PiP to bottom-right", () => {
    const { width, height } = screenOverlayPipSize({
      canvasWidth: 1280,
      cameraWidth: 640,
      cameraHeight: 360,
    })
    const pos = screenOverlayPipRect({
      canvasWidth: 1280,
      canvasHeight: 720,
      pipWidth: width,
      pipHeight: height,
      position: "bottom-right",
    })
    assert.ok(pos.x + width < 1280)
    assert.ok(pos.y + height < 720)
  })

  it("places corners inside margins", () => {
    const pipW = 200
    const pipH = 112
    const canvasW = 1000
    const canvasH = 600
    for (const position of [
      "top-left",
      "top-right",
      "bottom-left",
      "bottom-right",
    ] as const) {
      const { x, y } = screenOverlayPipRect({
        canvasWidth: canvasW,
        canvasHeight: canvasH,
        pipWidth: pipW,
        pipHeight: pipH,
        position,
      })
      assert.ok(x >= 0)
      assert.ok(y >= 0)
      assert.ok(x + pipW <= canvasW)
      assert.ok(y + pipH <= canvasH)
    }
  })
})
