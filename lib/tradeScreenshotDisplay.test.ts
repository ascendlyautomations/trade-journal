import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  DEFAULT_TRADE_SCREENSHOT_DISPLAY_MODE,
  resolveTradeScreenshotDisplayMode,
  TRADE_PAGE_SCREENSHOT_MAX_HEIGHT_CLASS,
  TRADE_PAGE_SCREENSHOT_PREVIEW_HEIGHT_PX,
  TRADE_SCREENSHOT_MAX_HEIGHT_PX,
  tradeScreenshotObjectFitClass,
} from "./tradeScreenshotDisplay.ts"

describe("tradeScreenshotDisplay", () => {
  it("caps feed thumbnail height", () => {
    assert.equal(TRADE_SCREENSHOT_MAX_HEIGHT_PX, 440)
  })

  it("uses a max-height class for Trades-page previews", () => {
    assert.equal(TRADE_PAGE_SCREENSHOT_MAX_HEIGHT_CLASS, "max-h-[396px]")
    assert.equal(TRADE_PAGE_SCREENSHOT_PREVIEW_HEIGHT_PX, 396)
  })

  it("defaults existing trades to fit", () => {
    assert.equal(DEFAULT_TRADE_SCREENSHOT_DISPLAY_MODE, "fit")
    assert.equal(resolveTradeScreenshotDisplayMode(null), "fit")
    assert.equal(resolveTradeScreenshotDisplayMode(undefined), "fit")
    assert.equal(resolveTradeScreenshotDisplayMode(""), "fit")
    assert.equal(resolveTradeScreenshotDisplayMode("FIT"), "fit")
  })

  it("resolves fill display mode", () => {
    assert.equal(resolveTradeScreenshotDisplayMode("fill"), "fill")
    assert.equal(resolveTradeScreenshotDisplayMode(" Fill "), "fill")
  })

  it("maps modes to object-fit classes", () => {
    assert.equal(tradeScreenshotObjectFitClass("fit"), "object-contain")
    assert.equal(tradeScreenshotObjectFitClass("fill"), "object-cover")
  })
})
