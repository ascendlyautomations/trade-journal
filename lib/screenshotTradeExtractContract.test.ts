import { describe, it } from "node:test"
import assert from "node:assert/strict"
import {
  SCREENSHOT_TRADE_EXTRACT_SCHEMA_VERSION,
  validateScreenshotTradeExtractRequest,
  validateScreenshotTradeExtractionResponse,
} from "./screenshotTradeExtractContract.ts"

describe("screenshotTradeExtractContract", () => {
  it("accepts valid extraction response", () => {
    const parsed = validateScreenshotTradeExtractionResponse({
      schemaVersion: SCREENSHOT_TRADE_EXTRACT_SCHEMA_VERSION,
      detectedPlatform: "tradovate",
      contentType: "executions",
      fills: [
        {
          symbol: { value: "MNQ", provenance: "observed" },
          side: { value: "buy", provenance: "observed" },
          quantity: { value: 2, provenance: "observed" },
          price: { value: 24100, provenance: "observed" },
          executedAt: { value: "2026-09-02 10:32", provenance: "observed" },
          sourceImageIndex: 0,
        },
      ],
      completedTrades: [],
      warnings: [],
      screenshotResults: [{ index: 0, tradeLike: true, warnings: [] }],
    })
    assert.equal(parsed?.fills.length, 1)
    assert.equal(parsed?.fills[0].symbol.value, "MNQ")
  })

  it("rejects unsupported schema version", () => {
    assert.equal(
      validateScreenshotTradeExtractionResponse({
        schemaVersion: "v2",
        contentType: "executions",
        fills: [],
        completedTrades: [],
        warnings: [],
        screenshotResults: [],
      }),
      null
    )
  })

  it("rejects malformed response content type", () => {
    assert.equal(
      validateScreenshotTradeExtractionResponse({
        schemaVersion: SCREENSHOT_TRADE_EXTRACT_SCHEMA_VERSION,
        detectedPlatform: null,
        contentType: "invalid",
        fills: [],
        completedTrades: [],
        warnings: [],
        screenshotResults: [],
      }),
      null
    )
  })

  it("validates request with jpeg screenshots", () => {
    const request = validateScreenshotTradeExtractRequest({
      schemaVersion: SCREENSHOT_TRADE_EXTRACT_SCHEMA_VERSION,
      screenshots: [
        {
          index: 0,
          mimeType: "image/jpeg",
          base64: "aGVsbG8=",
          ocrBlocks: [{ text: "MNQ", x: 0.1, y: 0.2, width: 0.1, height: 0.02 }],
        },
      ],
    })
    assert.equal(request?.screenshots.length, 1)
  })

  it("rejects empty screenshot list", () => {
    assert.equal(
      validateScreenshotTradeExtractRequest({
        schemaVersion: SCREENSHOT_TRADE_EXTRACT_SCHEMA_VERSION,
        screenshots: [],
      }),
      null
    )
  })
})
