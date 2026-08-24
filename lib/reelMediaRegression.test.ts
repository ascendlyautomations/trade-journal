import { describe, it } from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"

import { fileURLToPath } from "node:url"
const __dirname = path.dirname(fileURLToPath(import.meta.url))

const ROOT = path.join(__dirname, "..")

function read(relPath: string): string {
  return fs.readFileSync(path.join(ROOT, relPath), "utf8")
}

/**
 * Focused regression checklist for completed performance + Reel media work.
 * Complements lib/reelIdlePoster.test.ts, lib/feedReelMedia.test.ts, lib/phaseH3.requestOwnership.test.ts.
 */
describe("Performance closeout — regression invariants", () => {
  it("idle Trades-linked Reel attachment does not mount video", () => {
    const src = read("app/components/TradeReelAttachment.tsx")
    assert.match(src, /ReelIdlePoster/)
    assert.doesNotMatch(src, /<video/)
    assert.doesNotMatch(src, /videoUrl=/)
  })

  it("captureReelPosterFromUrl and getReelVideoFrameSource are removed from runtime", () => {
    const src = read("lib/reelVideo.ts")
    assert.doesNotMatch(src, /captureReelPosterFromUrl/)
    assert.doesNotMatch(src, /getReelVideoFrameSource/)
    assert.match(src, /captureReelVideoThumbnail/)
  })

  it("upload-time thumbnail capture remains scoped to local File workflow", () => {
    const reels = read("lib/reels.ts")
    assert.match(reels, /captureReelVideoThumbnail\(file\)/)
    assert.doesNotMatch(reels, /captureReelPosterFromUrl/)
  })

  it("ReelClipPlayback releases video source on viewer close", () => {
    const src = read("app/components/ReelClipPlayback.tsx")
    assert.match(src, /removeAttribute\("src"\)/)
    assert.match(src, /video\.load\(\)/)
  })

  it("community room unread is event-driven, not interval-polled", () => {
    const src = read("lib/communityRoomUnread.ts")
    assert.match(src, /no fixed-interval polling/)
    assert.doesNotMatch(src, /setInterval/)
  })

  it("feature-flag tests isolate developer env", () => {
    const src = read("lib/backendV2/flags.testIsolation.ts")
    assert.match(src, /delete process\.env\[key\]/)
    assert.match(src, /__resetBackendV2FlagsForTests/)
  })

  it("affiliate connect sync treats Stripe auth failure as deterministic", () => {
    const src = read("app/api/affiliates/connect/sync/route.ts")
    assert.match(src, /StripeAuthenticationError/)
    assert.match(src, /stripe_auth_invalid/)
  })
})
export {}
