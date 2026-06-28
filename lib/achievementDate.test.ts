const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  getDefaultAchievementDateInputValue,
  normalizeAchievementDateInputValue,
  resolveNewAchievementDateInputValue,
} = require("./achievementDate.ts")

describe("achievementDate", () => {
  const fixedNow = new Date(2026, 5, 28, 23, 30, 0)

  it("defaults new uploads to today's local date", () => {
    assert.equal(getDefaultAchievementDateInputValue(fixedNow), "2026-06-28")
    assert.equal(resolveNewAchievementDateInputValue(undefined), "2026-06-28")
  })

  it("keeps explicit initial achieved_at values", () => {
    assert.equal(
      resolveNewAchievementDateInputValue({ achieved_at: "2026-03-15" }),
      "2026-03-15"
    )
  })

  it("does not shift date-only strings through UTC", () => {
    assert.equal(normalizeAchievementDateInputValue("2026-06-01"), "2026-06-01")
  })
})
