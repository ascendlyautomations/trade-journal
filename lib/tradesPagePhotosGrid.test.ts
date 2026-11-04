import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  tradeHasScreenshotForPhotosGrid,
  tradesPagePhotoGridEntries,
} from "./tradesPagePhotosGrid.ts"

describe("tradesPagePhotosGrid", () => {
  it("includes only trades with screenshot paths", () => {
    assert.equal(tradeHasScreenshotForPhotosGrid({ image_url: "a.png" }), true)
    assert.equal(tradeHasScreenshotForPhotosGrid({ image_url: "" }), false)
    assert.equal(tradeHasScreenshotForPhotosGrid({}), false)

    const entries = tradesPagePhotoGridEntries([
      {
        kind: "single",
        trade: { id: "1", image_url: "shot.png" } as import("./copyTradePresentation.ts").CopyTradeWireRow,
      },
      { kind: "single", trade: { id: "2" } },
    ])
    assert.equal(entries.length, 1)
    assert.equal(entries[0]?.trade.id, "1")
    assert.ok(entries[0]?.previewUrl.includes("shot.png"))
  })
})
