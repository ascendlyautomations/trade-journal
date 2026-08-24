;(function () {
  const assert = require("node:assert/strict")
  const fs = require("node:fs")
  const path = require("node:path")
  const { describe, it } = require("node:test")

  const RENDER_SRC = path.join(__dirname, "renderTradeImageCrop.ts")
  const ASPECT_SRC = path.join(__dirname, "tradeImageAspect.ts")

  describe("renderTradeImageCrop", () => {
    it("uses the shared content frame dimensions", () => {
      const aspectSrc = fs.readFileSync(ASPECT_SRC, "utf8")
      assert.match(aspectSrc, /TRADE_IMAGE_OUTPUT_WIDTH = 1200/)
      assert.match(aspectSrc, /TRADE_IMAGE_OUTPUT_HEIGHT = 900/)
    })

    it("delegates fit preview math to zoom/pan draw rect", () => {
      const src = fs.readFileSync(RENDER_SRC, "utf8")
      assert.match(src, /computeFitDrawRect/)
      assert.match(src, /computeZoomPanDrawRect/)
      assert.match(src, /computeFitScale/)
    })
  })
})()
