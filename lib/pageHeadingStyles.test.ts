import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  PAGE_HEADING_ADMIN_CLASS,
  PAGE_HEADING_APP_CLASS,
  PAGE_HEADING_CENTERED_CLASS,
  PAGE_HEADING_COLOR_CLASS,
  PAGE_HEADING_LARGE_CLASS,
  PAGE_HEADING_MARKETING_CLASS,
} from "./pageHeadingStyles.ts"

describe("pageHeadingStyles", () => {
  it("uses solid blue-300 for all presets", () => {
    assert.equal(PAGE_HEADING_COLOR_CLASS, "text-blue-300")
    for (const preset of [
      PAGE_HEADING_CENTERED_CLASS,
      PAGE_HEADING_APP_CLASS,
      PAGE_HEADING_LARGE_CLASS,
      PAGE_HEADING_MARKETING_CLASS,
      PAGE_HEADING_ADMIN_CLASS,
    ]) {
      assert.ok(preset.includes("text-blue-300"))
      assert.ok(!preset.includes("gradient"))
      assert.ok(!preset.includes("text-transparent"))
    }
  })
})
