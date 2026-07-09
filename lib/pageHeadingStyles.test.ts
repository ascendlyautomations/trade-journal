import { describe, expect, it } from "vitest"
import {
  PAGE_HEADING_ADMIN_CLASS,
  PAGE_HEADING_APP_CLASS,
  PAGE_HEADING_CENTERED_CLASS,
  PAGE_HEADING_COLOR_CLASS,
  PAGE_HEADING_LARGE_CLASS,
} from "./pageHeadingStyles"

describe("pageHeadingStyles", () => {
  it("uses solid blue-300 for all presets", () => {
    expect(PAGE_HEADING_COLOR_CLASS).toBe("text-blue-300")
    for (const preset of [
      PAGE_HEADING_CENTERED_CLASS,
      PAGE_HEADING_APP_CLASS,
      PAGE_HEADING_LARGE_CLASS,
      PAGE_HEADING_ADMIN_CLASS,
    ]) {
      expect(preset).toContain("text-blue-300")
      expect(preset).not.toContain("gradient")
      expect(preset).not.toContain("text-transparent")
    }
  })
})
