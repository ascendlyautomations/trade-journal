import { describe, expect, it } from "vitest"
import { TRADE_IMAGE_OUTPUT_HEIGHT, TRADE_IMAGE_OUTPUT_WIDTH } from "./tradeImageAspect"
import { computeFitDrawRect } from "./renderTradeImageCrop"

describe("renderTradeImageCrop", () => {
  it("uses the shared content frame dimensions", () => {
    expect(TRADE_IMAGE_OUTPUT_WIDTH).toBe(1200)
    expect(TRADE_IMAGE_OUTPUT_HEIGHT).toBe(900)
  })

  it("delegates fit preview math to zoom/pan draw rect", () => {
    const rect = computeFitDrawRect(1600, 900)
    expect(rect.width).toBe(1200)
    expect(rect.height).toBeCloseTo(675)
    expect(rect.x).toBeCloseTo(0)
    expect(rect.y).toBeGreaterThan(0)
  })
})
