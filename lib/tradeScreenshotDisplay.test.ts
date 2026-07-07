import { describe, expect, it } from "vitest"
import { resolveTradeScreenshotLayout } from "./tradeScreenshotDisplay"

describe("tradeScreenshotDisplay", () => {
  it("keeps landscape and square images natural", () => {
    expect(resolveTradeScreenshotLayout(1600, 900)).toBe("natural")
    expect(resolveTradeScreenshotLayout(1000, 1000)).toBe("natural")
  })

  it("crops only extremely tall images", () => {
    expect(resolveTradeScreenshotLayout(900, 1600)).toBe("tall-crop")
  })
})
