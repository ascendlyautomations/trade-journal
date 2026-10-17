import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  isOptimizedStorageObjectPath,
  optimizedStorageObjectPath,
  resolveStoredRoomImageUrl,
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

  it("turns stored room avatar paths into avatars object URLs", () => {
    const base = "https://abc.supabase.co"
    assert.equal(
      resolveStoredRoomImageUrl("room-images/1788923667-avatar.jpg", base),
      `${base}/storage/v1/object/public/avatars/room-images/1788923667-avatar.jpg`
    )
    assert.equal(
      resolveStoredRoomImageUrl(
        "3daf15b8-2f5d-48c8-ac98-75bca6c878f4/room-images/opt/1791222768072.jpg",
        base
      ),
      `${base}/storage/v1/object/public/avatars/3daf15b8-2f5d-48c8-ac98-75bca6c878f4/room-images/opt/1791222768072.jpg`
    )
    assert.equal(
      resolveStoredRoomImageUrl(`${base}/storage/v1/object/public/avatars/a.jpg`, base),
      `${base}/storage/v1/object/public/avatars/a.jpg`
    )
    assert.equal(resolveStoredRoomImageUrl("/default-avatar.png", base), "/default-avatar.png")
  })

  it("normalizes render URLs to object URLs", () => {
    const render =
      "https://abc.supabase.co/storage/v1/render/image/public/avatars/u1/opt/1.jpg?width=96"
    const object = toSupabaseObjectPublicUrl(render)
    assert.ok(object.includes("/storage/v1/object/public/avatars/u1/opt/1.jpg"))
    assert.ok(!object.includes("width="))
  })
})
