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

describe("Feed Reel media — zero video before intentional activation", () => {
  it("FeedReelCard idle card uses ReelThumbnailPreview without video element", () => {
    const src = read("app/components/feed/FeedReelCard.tsx")
    assert.match(src, /ReelThumbnailPreview/)
    assert.doesNotMatch(src, /<video/)
    assert.doesNotMatch(src, /video_url/)
  })

  it("FeedPostBody linked reel preview does not mount video", () => {
    const src = read("app/components/feed/FeedPostBody.tsx")
    assert.match(src, /ReelThumbnailPreview/)
    assert.doesNotMatch(src, /<video/)
    assert.doesNotMatch(src, /video_url/)
  })

  it("FeedPostDetailModal attached reel preview does not mount video", () => {
    const src = read("app/components/feed/FeedPostDetailModal.tsx")
    assert.match(src, /ReelThumbnailPreview/)
    assert.doesNotMatch(src, /<video/)
    assert.doesNotMatch(src, /DetailModalVideo/)
  })

  it("FeedPostList routes reel posts through FeedReelCard only", () => {
    const src = read("app/components/feed/FeedPostList.tsx")
    assert.match(src, /feedKind === "reel"/)
    assert.match(src, /FeedReelCard/)
    assert.doesNotMatch(src, /<video/)
  })

  it("FeedPostOverlays mounts FeedReelDetailModal only when a post is selected", () => {
    const src = read("app/components/feed/FeedPostOverlays.tsx")
    assert.match(src, /selectedPost && selectedPostId/)
    assert.match(src, /FeedReelDetailModal/)
    assert.doesNotMatch(src, /FeedReelDetailModal[\s\S]*selectedPostId === null/)
  })

  it("ReelThumbnailPreview passes only thumbnail URL to ReelIdlePoster", () => {
    const src = read("app/components/ReelThumbnailPreview.tsx")
    assert.match(src, /ReelIdlePoster/)
    assert.match(src, /thumbnailUrl=\{reel\.thumbnail_url\}/)
    assert.doesNotMatch(src, /videoUrl=/)
    assert.doesNotMatch(src, /video_url/)
    assert.doesNotMatch(src, /<video/)
  })

  it("ReelIdlePoster never references video URLs or mounts video", () => {
    const src = read("app/components/ReelIdlePoster.tsx")
    assert.doesNotMatch(src, /<video/)
    assert.doesNotMatch(src, /videoUrl/)
    assert.doesNotMatch(src, /video_url/)
    assert.doesNotMatch(src, /captureReelPosterFromUrl/)
    assert.doesNotMatch(src, /IntersectionObserver/)
  })

  it("Feed page does not render video players in list markup", () => {
    const src = read("app/(app)/feed/page.tsx")
    assert.doesNotMatch(src, /<video/)
    assert.doesNotMatch(src, /ReelClipPlayback/)
    assert.doesNotMatch(src, /DetailModalVideo/)
  })

  it("FeedReelDetailModal assigns video only in intentional viewer shell", () => {
    const src = read("app/components/feed/FeedReelDetailModal.tsx")
    assert.match(src, /DetailModalVideo/)
    assert.match(src, /post\.video_url/)
    assert.match(src, /removeAttribute\("src"\)/)
    assert.match(src, /video\.load\(\)/)
  })

  it("ReelClipPlayback does not seek or autoplay before intentional play", () => {
    const src = read("app/components/ReelClipPlayback.tsx")
    assert.match(src, /preload="metadata"/)
    assert.match(src, /removeAttribute\("src"\)/)
    assert.doesNotMatch(src, /firstVisibleReelSeekTime/)
    assert.doesNotMatch(src, /captureReelPosterFromUrl/)
    assert.doesNotMatch(src, /IntersectionObserver/)
    assert.doesNotMatch(src, /preload="auto"/)
  })

  it("Profile idle poster behavior remains unchanged", () => {
    const profileCard = read("app/components/profile/ProfileReelCard.tsx")
    assert.match(profileCard, /ReelIdlePoster/)
    assert.doesNotMatch(profileCard, /<video/)
    assert.doesNotMatch(profileCard, /video_url/)
  })

  it("ReelVideoPosterFrame and ReelNativeVideoThumb remain removed", () => {
    assert.throws(() => read("app/components/ReelVideoPosterFrame.tsx"), /ENOENT/)
    assert.throws(() => read("app/components/ReelNativeVideoThumb.tsx"), /ENOENT/)
  })
})
export {}
