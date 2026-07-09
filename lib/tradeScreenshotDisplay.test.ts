import { describe, expect, it } from "vitest"
import { TRADE_SCREENSHOT_MAX_HEIGHT_PX } from "./tradeScreenshotDisplay"

describe("tradeScreenshotDisplay", () => {
  it("caps feed thumbnail height", () => {
    expect(TRADE_SCREENSHOT_MAX_HEIGHT_PX).toBe(560)
  })
})
