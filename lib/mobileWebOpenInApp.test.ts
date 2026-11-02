import { describe, it } from "node:test"
import assert from "node:assert/strict"
import {
  MOBILE_WEB_UNIVERSAL_LINK_ORIGIN,
  mobileWebOpenInAppContentLink,
  mobileWebOpenInAppLink,
} from "./mobileWebOpenInApp.ts"

describe("mobileWebOpenInApp", () => {
  it("uses the official https host for supported content", () => {
    assert.equal(MOBILE_WEB_UNIVERSAL_LINK_ORIGIN, "https://www.tradetraxs.com")
    assert.deepEqual(mobileWebOpenInAppLink("/profile/nrltrades"), {
      kind: "profile",
      href: "https://www.tradetraxs.com/profile/nrltrades",
    })
    assert.deepEqual(mobileWebOpenInAppLink("/trade/abc-123"), {
      kind: "trade",
      href: "https://www.tradetraxs.com/trade/abc-123",
    })
    assert.deepEqual(mobileWebOpenInAppLink("/post/post-1"), {
      kind: "post",
      href: "https://www.tradetraxs.com/post/post-1",
    })
    assert.deepEqual(mobileWebOpenInAppLink("/reel/reel-1"), {
      kind: "clip",
      href: "https://www.tradetraxs.com/reel/reel-1",
    })
    assert.deepEqual(mobileWebOpenInAppLink("/feed", "?post=post-1"), {
      kind: "post",
      href: "https://www.tradetraxs.com/feed?post=post-1",
    })
    assert.deepEqual(mobileWebOpenInAppLink("/feed", "reel=reel-1"), {
      kind: "clip",
      href: "https://www.tradetraxs.com/feed?reel=reel-1",
    })
    assert.deepEqual(mobileWebOpenInAppLink("/feed", "trade=t1&post=p1"), {
      kind: "trade",
      href: "https://www.tradetraxs.com/feed?trade=t1",
    })
  })

  it("does not invent clips paths, custom schemes, or unrelated routes", () => {
    assert.equal(mobileWebOpenInAppLink("/clips/reel-1"), null)
    assert.equal(mobileWebOpenInAppLink("/profile"), null)
    assert.equal(mobileWebOpenInAppLink("/dashboard"), null)
    assert.equal(mobileWebOpenInAppLink("/messages/thread-1"), null)
    assert.equal(mobileWebOpenInAppLink("/feed"), null)
    assert.equal(mobileWebOpenInAppLink("/feed", "achievement=ach-1"), null)
    assert.equal(mobileWebOpenInAppLink("/trade/"), null)
    assert.equal(mobileWebOpenInAppContentLink("clip", "a/b"), null)
    assert.equal(mobileWebOpenInAppContentLink("post", "  "), null)
    const clip = mobileWebOpenInAppContentLink("clip", "reel 1")
    assert.equal(clip, null)
    const post = mobileWebOpenInAppContentLink("post", "post-1")
    assert.equal(post?.href.startsWith("https://www.tradetraxs.com/post/"), true)
    assert.equal(post?.href.includes("tradetraxs://"), false)
  })
})
