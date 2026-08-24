import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  inferAvatarPixelSize,
  isSupabaseStoragePublicUrl,
  optimizeStorageImageUrl,
  toSupabaseRenderUrl,
} from "./optimizedStorageImage.ts"

const SAMPLE_OBJECT_URL =
  "https://abc.supabase.co/storage/v1/object/public/screenshots/user/trade.webp"

describe("optimizedStorageImage", () => {
  it("detects supabase public storage URLs", () => {
    assert.equal(isSupabaseStoragePublicUrl(SAMPLE_OBJECT_URL), true)
    assert.equal(isSupabaseStoragePublicUrl("https://cdn.example.com/a.png"), false)
  })

  it("converts object URL to render URL with transform params", () => {
    const out = toSupabaseRenderUrl(SAMPLE_OBJECT_URL, {
      width: 800,
      quality: 75,
      resize: "contain",
    })
    assert.ok(out.includes("/storage/v1/render/image/public/screenshots/"))
    assert.ok(out.includes("width=800"))
    assert.ok(out.includes("quality=75"))
    assert.ok(out.includes("resize=contain"))
  })

  it("optimizes trade thumb preset for supabase URLs", () => {
    const out = optimizeStorageImageUrl(SAMPLE_OBJECT_URL, "trade-thumb")
    assert.ok(out)
    assert.ok(out.includes("render/image/public"))
    assert.ok(out.includes("width=800"))
  })

  it("passes through non-supabase http URLs unchanged", () => {
    const external = "https://picsum.photos/800/600"
    assert.equal(optimizeStorageImageUrl(external, "trade-thumb"), external)
  })

  it("passes through local static paths unchanged", () => {
    assert.equal(optimizeStorageImageUrl("/images/demo.png", "trade-thumb"), "/images/demo.png")
  })

  it("infers avatar pixel size from tailwind classes", () => {
    assert.equal(inferAvatarPixelSize("h-10 w-10"), 80)
    assert.equal(inferAvatarPixelSize("h-8 w-8"), 64)
    assert.equal(inferAvatarPixelSize(""), 80)
  })
})
