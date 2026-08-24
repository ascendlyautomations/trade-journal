import { describe, it, beforeEach } from "node:test"
import { isMessagingV2CachedUnavailable, markMessagingV2Unavailable, resetMessagingV2AvailabilityForTests, } from "./backendV2/messagingV2Availability.ts"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"

import { fileURLToPath } from "node:url"
const __dirname = path.dirname(fileURLToPath(import.meta.url))

describe("Phase D — messaging V2 availability cache", () => {
  beforeEach(() => {
    resetMessagingV2AvailabilityForTests()
  })

  it("starts unavailable=false", () => {
    assert.equal(isMessagingV2CachedUnavailable(), false)
  })

  it("marks and reads session unavailable flag", () => {
    markMessagingV2Unavailable()
    assert.equal(isMessagingV2CachedUnavailable(), true)
    resetMessagingV2AvailabilityForTests()
    assert.equal(isMessagingV2CachedUnavailable(), false)
  })
})

describe("Phase D — wiring audits", () => {
  it("repository skips V2 probe when cached unavailable", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "backendV2/messagingBootstrapRepository.ts"),
      "utf8"
    )
    assert.match(src, /isMessagingV2CachedUnavailable/)
    assert.match(src, /markMessagingV2Unavailable/)
    assert.match(src, /clearMessagingV2UnavailableCache/)
  })

  it("fetchReelsByTradeIds uses lightweight select", () => {
    const src = fs.readFileSync(path.join(__dirname, "reels.ts"), "utf8")
    const fn = src.slice(
      src.indexOf("async function queryReelsByTradeIds"),
      src.indexOf("function filterProfileListedReels")
    )
    assert.match(fn, /\.select\(REEL_ROW_SELECT\)/)
    assert.doesNotMatch(fn, /PROFILE_REELS_SELECT/)
  })

  it("Vercel insights gated to deployed runtime", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "../app/components/NativeAwareVercelInsights.tsx"),
      "utf8"
    )
    assert.match(src, /isVercelHostedRuntime/)
    assert.match(src, /NEXT_PUBLIC_VERCEL/)
  })

  it("trade cards use transformed screenshot preview", () => {
    const card = fs.readFileSync(
      path.join(__dirname, "../app/components/TradesPageTradeCard.tsx"),
      "utf8"
    )
    const preview = fs.readFileSync(
      path.join(__dirname, "../app/components/ui/TradeScreenshotPreview.tsx"),
      "utf8"
    )
    assert.match(card, /TradeScreenshotPreview/)
    assert.match(preview, /preset="trade-thumb"/)
  })
})
export {}
