import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  isOptimizedStorageObjectPath,
  optimizedStorageObjectPath,
  storagePublicPathFromUrl,
  toSupabaseObjectPublicUrl,
} from "./storageOptimizedMedia.ts"

describe("storageOptimizedMedia", () => {
  it("builds paths under /opt/", () => {
    const path = optimizedStorageObjectPath("user-1", "jpg")
    assert.match(path, /^user-1\/opt\/\d+\.jpg$/)
    assert.equal(isOptimizedStorageObjectPath(path), true)
  })

  it("detects optimized assets from public object URLs", () => {
    const url =
      "https://abc.supabase.co/storage/v1/object/public/avatars/u1/opt/123.jpg"
    assert.equal(isOptimizedStorageObjectPath(url), true)
    assert.equal(
      storagePublicPathFromUrl(url),
      "avatars/u1/opt/123.jpg"
    )
  })

  it("treats legacy paths as non-optimized", () => {
    const url =
      "https://abc.supabase.co/storage/v1/object/public/screenshots/u1/123-trade.jpg"
    assert.equal(isOptimizedStorageObjectPath(url), false)
  })

  it("normalizes render URLs to object URLs", () => {
    const render =
      "https://abc.supabase.co/storage/v1/render/image/public/avatars/u1/opt/1.jpg?width=96"
    const object = toSupabaseObjectPublicUrl(render)
    assert.ok(object.includes("/storage/v1/object/public/avatars/u1/opt/1.jpg"))
    assert.ok(!object.includes("width="))
  })
})
