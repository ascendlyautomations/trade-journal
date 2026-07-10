import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { ACHIEVEMENT_TYPE } from "./achievementTypes.ts"
import {
  buildAchievementValidationPopup,
  collectAchievementFormMissingFields,
  validateAchievementForm,
} from "./validateAchievementForm.ts"

const BASE = {
  achievement_type: ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT,
  title: "First payout",
  payout_amount: "1500",
  achieved_at: "2026-01-15",
  hasImage: true,
}

describe("validateAchievementForm", () => {
  it("passes when all required fields are present", () => {
    const result = validateAchievementForm(BASE)
    assert.equal(result.ok, true)
  })

  it("collects multiple missing fields", () => {
    const missing = collectAchievementFormMissingFields({
      ...BASE,
      title: "",
      payout_amount: "",
      achieved_at: "",
      hasImage: false,
    })
    assert.deepEqual(missing, [
      "title",
      "payout_amount",
      "achieved_at",
      "image",
    ])
  })

  it("does not require payout for milestone achievements", () => {
    const missing = collectAchievementFormMissingFields({
      ...BASE,
      achievement_type: ACHIEVEMENT_TYPE.MILESTONE,
      payout_amount: "",
    })
    assert.equal(missing.includes("payout_amount"), false)
  })

  it("flags invalid payout amounts", () => {
    const result = validateAchievementForm({
      ...BASE,
      payout_amount: "0",
    })
    assert.equal(result.ok, false)
    if (result.ok || result.kind !== "invalid") {
      assert.fail("expected invalid payout")
    }
    assert.equal(result.field, "payout_amount")
  })

  it("flags a single missing title", () => {
    const result = validateAchievementForm({
      ...BASE,
      title: "   ",
    })
    assert.equal(result.ok, false)
    if (result.ok || result.kind !== "missing") {
      assert.fail("expected missing title")
    }
    assert.deepEqual(result.fields, ["title"])
  })

  it("builds a single-field popup for missing title", () => {
    const result = validateAchievementForm({
      ...BASE,
      title: "",
    })
    assert.equal(result.ok, false)
    if (result.ok) {
      assert.fail("expected validation failure")
    }
    const popup = buildAchievementValidationPopup(result)
    assert.equal(popup.title, "Title Required")
    assert.equal(popup.message, "Please enter an achievement title.")
    assert.equal(popup.type, "error")
    assert.equal(popup.persist, true)
  })

  it("builds a combined popup for multiple missing fields", () => {
    const result = validateAchievementForm({
      ...BASE,
      title: "",
      payout_amount: "",
      accountId: "",
      requiresTradingAccount: true,
    })
    assert.equal(result.ok, false)
    if (result.ok) {
      assert.fail("expected validation failure")
    }
    const popup = buildAchievementValidationPopup(result)
    assert.equal(popup.title, "Complete Required Fields")
    assert.match(popup.message, /Achievement Title/)
    assert.match(popup.message, /Payout Amount/)
    assert.match(popup.message, /Trading Account/)
    assert.match(popup.message, /before posting your achievement\./)
  })
})
