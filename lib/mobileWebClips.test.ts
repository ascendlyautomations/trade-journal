import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  formatMobileWebClipCount,
  isMobileWebClipsImmersive,
  readMobileWebClipsPostId,
  setMobileWebClipsImmersive,
  writeMobileWebClipsPostId,
} from "./mobileWebClips.ts"

describe("formatMobileWebClipCount", () => {
  it("hides zero and formats compact counts", () => {
    assert.equal(formatMobileWebClipCount(0), null)
    assert.equal(formatMobileWebClipCount(12), "12")
    assert.equal(formatMobileWebClipCount(1540), "1.5k")
    assert.equal(formatMobileWebClipCount(12500), "13k")
  })
})

describe("clips scroll restore", () => {
  it("remembers the last clip id", () => {
    const store = new Map<string, string>()
    Object.defineProperty(globalThis, "sessionStorage", {
      configurable: true,
      value: {
        getItem: (key: string) => store.get(key) ?? null,
        setItem: (key: string, value: string) => {
          store.set(key, value)
        },
        removeItem: (key: string) => {
          store.delete(key)
        },
      },
    })
    writeMobileWebClipsPostId("clip-9")
    assert.equal(readMobileWebClipsPostId(), "clip-9")
    writeMobileWebClipsPostId("")
    assert.equal(readMobileWebClipsPostId(), null)
  })
})

describe("setMobileWebClipsImmersive", () => {
  it("tracks immersive state for navbar subscribers", () => {
    setMobileWebClipsImmersive(true)
    assert.equal(isMobileWebClipsImmersive(), true)
    setMobileWebClipsImmersive(false)
    assert.equal(isMobileWebClipsImmersive(), false)
  })
})
