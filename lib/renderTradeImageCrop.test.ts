import { describe, expect, it } from "vitest"
import {
  clampFillOffset,
  computeFillDrawRect,
  computeFitDrawRect,
  computeFitExportSize,
} from "./renderTradeImageCrop"

describe("renderTradeImageCrop", () => {
  it("exports fit images at natural aspect without padding", () => {
    const size = computeFitExportSize(1600, 900)
    expect(size.width).toBe(1200)
    expect(size.height).toBe(675)
  })

  it("fits a wide image inside the fill frame for preview math", () => {
    const rect = computeFitDrawRect(1600, 900, 1200, 900)
    expect(rect.width).toBe(1200)
    expect(rect.height).toBeCloseTo(675)
    expect(rect.x).toBeCloseTo(0)
    expect(rect.y).toBeGreaterThan(0)
  })

  it("fills a tall image and clamps drag offsets", () => {
    const rect = computeFillDrawRect(900, 1600, { x: 500, y: -2000 }, 1200, 900)
    expect(rect.width).toBeGreaterThanOrEqual(1200)
    expect(rect.height).toBeGreaterThanOrEqual(900)
    expect(rect.x).toBeLessThanOrEqual(0)
    expect(rect.y).toBeLessThanOrEqual(0)

    const clamped = clampFillOffset(
      rect.width,
      rect.height,
      { x: 500, y: -2000 },
      1200,
      900
    )
    expect(clamped.x).toBe(0)
    expect(clamped.y).toBe(900 - rect.height)
  })
})
