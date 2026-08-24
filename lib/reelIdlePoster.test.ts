import { describe, it } from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"

import { fileURLToPath } from "node:url"
const __dirname = path.dirname(fileURLToPath(import.meta.url))

const ROOT = path.join(__dirname, "..")

describe("Reel idle poster — zero video before intentional play", () => {
  it("ReelIdlePoster renders image or static placeholder only", () => {
    const src = fs.readFileSync(
      path.join(ROOT, "app/components/ReelIdlePoster.tsx"),
      "utf8"
    )
    assert.match(src, /getReelPosterImageUrl/)
    assert.match(src, /StorageImage/)
    assert.match(src, /bg-gradient-to-br/)
    assert.doesNotMatch(src, /<video/)
    assert.doesNotMatch(src, /videoUrl/)
    assert.doesNotMatch(src, /captureReelPosterFromUrl/)
    assert.doesNotMatch(src, /getReelVideoFrameSource/)
    assert.doesNotMatch(src, /IntersectionObserver/)
  })

  it("ReelThumbnailPreview uses ReelIdlePoster without video URL", () => {
    const src = fs.readFileSync(
      path.join(ROOT, "app/components/ReelThumbnailPreview.tsx"),
      "utf8"
    )
    assert.match(src, /ReelIdlePoster/)
    assert.match(src, /thumbnailUrl=\{reel\.thumbnail_url\}/)
    assert.doesNotMatch(src, /videoUrl=/)
    assert.doesNotMatch(src, /<video/)
  })

  it("ProfileReelCard uses ReelIdlePoster without video URL", () => {
    const src = fs.readFileSync(
      path.join(ROOT, "app/components/profile/ProfileReelCard.tsx"),
      "utf8"
    )
    assert.match(src, /ReelIdlePoster/)
    assert.doesNotMatch(src, /video_url/)
    assert.doesNotMatch(src, /<video/)
  })

  it("TradeReelAttachment attached preview uses ReelIdlePoster only", () => {
    const src = fs.readFileSync(
      path.join(ROOT, "app/components/TradeReelAttachment.tsx"),
      "utf8"
    )
    assert.match(src, /ReelIdlePoster/)
    assert.doesNotMatch(src, /ReelVideoPosterFrame/)
    assert.doesNotMatch(src, /videoUrl=/)
  })

  it("ReelComposerModal edit preview does not mount video", () => {
    const src = fs.readFileSync(
      path.join(ROOT, "app/components/profile/ReelComposerModal.tsx"),
      "utf8"
    )
    assert.match(src, /ReelIdlePoster/)
    assert.doesNotMatch(src, /<video/)
    assert.doesNotMatch(src, /ReelVideoPosterFrame/)
  })

  it("Feed cards route through ReelThumbnailPreview", () => {
    const feedCard = fs.readFileSync(
      path.join(ROOT, "app/components/feed/FeedReelCard.tsx"),
      "utf8"
    )
    const feedBody = fs.readFileSync(
      path.join(ROOT, "app/components/feed/FeedPostBody.tsx"),
      "utf8"
    )
    assert.match(feedCard, /ReelThumbnailPreview/)
    assert.match(feedBody, /ReelThumbnailPreview/)
  })

  it("ReelViewer mounts video only in intentional playback shell", () => {
    const viewer = fs.readFileSync(
      path.join(ROOT, "app/components/profile/ReelViewer.tsx"),
      "utf8"
    )
    const idle = fs.readFileSync(
      path.join(ROOT, "app/components/ReelIdlePoster.tsx"),
      "utf8"
    )
    assert.match(viewer, /DetailModalVideo/)
    assert.match(viewer, /reel\.video_url/)
    assert.doesNotMatch(idle, /reel\.video_url/)
  })

  it("ReelClipPlayback releases video source on unmount and avoids browser poster extraction", () => {
    const src = fs.readFileSync(
      path.join(ROOT, "app/components/ReelClipPlayback.tsx"),
      "utf8"
    )
    assert.match(src, /removeAttribute\("src"\)/)
    assert.match(src, /video\.load\(\)/)
    assert.match(src, /preload="metadata"/)
    assert.doesNotMatch(src, /firstVisibleReelSeekTime/)
    assert.doesNotMatch(src, /captureReelPosterFromUrl/)
  })

  it("ReelVideoPosterFrame and ReelNativeVideoThumb idle loaders are removed", () => {
    assert.throws(
      () =>
        fs.readFileSync(
          path.join(ROOT, "app/components/ReelVideoPosterFrame.tsx"),
          "utf8"
        ),
      /ENOENT/
    )
    assert.throws(
      () =>
        fs.readFileSync(
          path.join(ROOT, "app/components/ReelNativeVideoThumb.tsx"),
          "utf8"
        ),
      /ENOENT/
    )
  })

  it("getReelPosterImageUrl rejects video URLs as thumbnails", () => {
    const src = fs.readFileSync(path.join(__dirname, "reelVideo.ts"), "utf8")
    assert.match(src, /function getReelPosterImageUrl/)
    assert.match(src, /isReelVideoMediaUrl\(raw\)/)
    assert.match(src, /return null/)
  })
})
export {}
