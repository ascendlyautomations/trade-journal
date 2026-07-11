import { describe, expect, it } from "vitest"
import {
  DEFAULT_TRADE_SCREENSHOT_DISPLAY_MODE,
  resolveTradeScreenshotDisplayMode,
  TRADE_PAGE_SCREENSHOT_MAX_HEIGHT_CLASS,
  TRADE_PAGE_SCREENSHOT_PREVIEW_HEIGHT_PX,
  TRADE_SCREENSHOT_MAX_HEIGHT_PX,
  tradeScreenshotObjectFitClass,
} from "./tradeScreenshotDisplay"

describe("tradeScreenshotDisplay", () => {
  it("caps feed thumbnail height", () => {
    expect(TRADE_SCREENSHOT_MAX_HEIGHT_PX).toBe(560)
  })

  it("uses a max-height class for Trades-page previews", () => {
    expect(TRADE_PAGE_SCREENSHOT_MAX_HEIGHT_CLASS).toBe("max-h-[396px]")
    expect(TRADE_PAGE_SCREENSHOT_PREVIEW_HEIGHT_PX).toBe(396)
  })

  it("defaults existing trades to fit", () => {
    expect(DEFAULT_TRADE_SCREENSHOT_DISPLAY_MODE).toBe("fit")
    expect(resolveTradeScreenshotDisplayMode(null)).toBe("fit")
    expect(resolveTradeScreenshotDisplayMode(undefined)).toBe("fit")
    expect(resolveTradeScreenshotDisplayMode("")).toBe("fit")
    expect(resolveTradeScreenshotDisplayMode("FIT")).toBe("fit")
  })

  it("resolves fill display mode", () => {
    expect(resolveTradeScreenshotDisplayMode("fill")).toBe("fill")
    expect(resolveTradeScreenshotDisplayMode(" Fill ")).toBe("fill")
  })

  it("maps modes to object-fit classes", () => {
    expect(tradeScreenshotObjectFitClass("fit")).toBe("object-contain")
    expect(tradeScreenshotObjectFitClass("fill")).toBe("object-cover")
  })
})
