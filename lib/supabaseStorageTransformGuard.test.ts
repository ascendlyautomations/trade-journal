import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  assertNoSupabaseStorageTransformUrl,
  isSupabaseStorageTransformUrl,
  supabaseStorageDeliveryUrl,
} from "./supabaseStorageTransformGuard.ts"
import { optimizeStorageImageUrl } from "./optimizedStorageImage.ts"

const SAMPLE_OBJECT =
  "https://abc.supabase.co/storage/v1/object/public/screenshots/user/trade.webp"
const SAMPLE_RENDER =
  "https://abc.supabase.co/storage/v1/render/image/public/screenshots/user/trade.webp?width=640&quality=75"

describe("supabaseStorageTransformGuard", () => {
  it("detects render URLs", () => {
    assert.equal(isSupabaseStorageTransformUrl(SAMPLE_RENDER), true)
    assert.equal(isSupabaseStorageTransformUrl(SAMPLE_OBJECT), false)
  })

  it("normalizes render URLs to object/public", () => {
    const out = supabaseStorageDeliveryUrl(SAMPLE_RENDER)
    assert.ok(out.includes("/storage/v1/object/public/"))
    assert.ok(!out.includes("render/image"))
    assert.ok(!out.includes("width="))
  })

  it("optimizeStorageImageUrl never returns transform URLs for any preset", () => {
    const presets = [
      "avatar",
      "feed-thumb",
      "feed-card",
      "feed-detail",
      "story",
      "reel-thumb",
      "achievement",
      "achievement-card",
      "trade-thumb",
      "message-preview",
      "message-thumb",
      "message-story-thumb",
      "room-thumb",
      "room-list-thumb",
    ] as const
    for (const preset of presets) {
      const out = optimizeStorageImageUrl(SAMPLE_OBJECT, preset)
      assert.ok(out, preset)
      assertNoSupabaseStorageTransformUrl(out!, preset)
    }
  })

  it("assertNoSupabaseStorageTransformUrl throws on render URLs", () => {
    assert.throws(() => assertNoSupabaseStorageTransformUrl(SAMPLE_RENDER))
  })
})
