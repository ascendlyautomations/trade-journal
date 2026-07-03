import { describe, expect, it } from "vitest"
import {
  inferAvatarPixelSize,
  isSupabaseStoragePublicUrl,
  optimizeStorageImageUrl,
  toSupabaseRenderUrl,
} from "./optimizedStorageImage"

const SAMPLE_OBJECT_URL =
  "https://abc.supabase.co/storage/v1/object/public/screenshots/user/trade.webp"

describe("optimizedStorageImage", () => {
  it("detects supabase public storage URLs", () => {
    expect(isSupabaseStoragePublicUrl(SAMPLE_OBJECT_URL)).toBe(true)
    expect(isSupabaseStoragePublicUrl("https://cdn.example.com/a.png")).toBe(
      false
    )
  })

  it("converts object URL to render URL with transform params", () => {
    const out = toSupabaseRenderUrl(SAMPLE_OBJECT_URL, {
      width: 800,
      quality: 75,
      resize: "contain",
    })
    expect(out).toContain("/storage/v1/render/image/public/screenshots/")
    expect(out).toContain("width=800")
    expect(out).toContain("quality=75")
    expect(out).toContain("resize=contain")
  })

  it("optimizes trade thumb preset for supabase URLs", () => {
    const out = optimizeStorageImageUrl(SAMPLE_OBJECT_URL, "trade-thumb")
    expect(out).toContain("render/image/public")
    expect(out).toContain("width=800")
  })

  it("passes through non-supabase http URLs unchanged", () => {
    const external = "https://picsum.photos/800/600"
    expect(optimizeStorageImageUrl(external, "trade-thumb")).toBe(external)
  })

  it("passes through local static paths unchanged", () => {
    expect(optimizeStorageImageUrl("/images/demo.png", "trade-thumb")).toBe(
      "/images/demo.png"
    )
  })

  it("infers avatar pixel size from tailwind classes", () => {
    expect(inferAvatarPixelSize("h-10 w-10")).toBe(80)
    expect(inferAvatarPixelSize("h-8 w-8")).toBe(64)
    expect(inferAvatarPixelSize("")).toBe(80)
  })
})
