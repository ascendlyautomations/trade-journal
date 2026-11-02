import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { phoneWebThumbnailSrc } from "./mobileWebMedia.ts"

describe("phoneWebThumbnailSrc", () => {
  it("keeps an empty value empty", () => {
    assert.equal(phoneWebThumbnailSrc("  ", 256), null)
    assert.equal(phoneWebThumbnailSrc(null, 256), null)
  })

  it("resizes a local public image through the existing optimizer", () => {
    assert.equal(
      phoneWebThumbnailSrc("/images/shot.png", 256),
      "/_next/image?url=%2Fimages%2Fshot.png&w=256&q=75"
    )
  })

  it("resizes a public storage object and leaves other urls alone", () => {
    const storage =
      "https://example.supabase.co/storage/v1/object/public/trade-images/shot.png"
    assert.equal(
      phoneWebThumbnailSrc(storage, 384),
      `/_next/image?url=${encodeURIComponent(storage)}&w=384&q=75`
    )
    assert.equal(
      phoneWebThumbnailSrc("https://cdn.example/shot.png", 256),
      "https://cdn.example/shot.png"
    )
    assert.equal(phoneWebThumbnailSrc("blob:http://localhost/abc", 256), "blob:http://localhost/abc")
  })
})
