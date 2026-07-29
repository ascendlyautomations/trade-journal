const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  isCommentNotificationAllowed,
  isNotificationPreferenceEnabled,
  mapNotificationPreferencesRow,
} = require("./notificationPreferences.ts")

describe("notification preferences", () => {
  const base = mapNotificationPreferencesRow(null, "user-1")

  it("master toggle disables delivery checks", () => {
    const prefs = { ...base, notifications_enabled: false, likes_enabled: true }
    assert.equal(isCommentNotificationAllowed(prefs, "comment", false), false)
    assert.equal(
      isNotificationPreferenceEnabled(prefs, "likes_enabled"),
      false
    )
  })

  it("gates likes vs achievement comments separately", () => {
    const prefs = {
      ...base,
      comments_enabled: false,
      achievement_comments_enabled: true,
    }
    assert.equal(isCommentNotificationAllowed(prefs, "comment", false), false)
    assert.equal(isCommentNotificationAllowed(prefs, "comment", true), true)
  })

  it("gates replies and mentions", () => {
    const prefs = {
      ...base,
      replies_enabled: false,
      mentions_enabled: false,
      comments_enabled: true,
    }
    assert.equal(isCommentNotificationAllowed(prefs, "reply", false), false)
    assert.equal(isCommentNotificationAllowed(prefs, "mention", false), false)
    assert.equal(isCommentNotificationAllowed(prefs, "comment", false), true)
  })

  it("maps missing rows to defaults (all enabled)", () => {
    assert.equal(base.notifications_enabled, true)
    assert.equal(base.story_replies_enabled, true)
    assert.equal(base.shares_enabled, true)
    assert.equal(base.product_updates_enabled, true)
    assert.equal(base.follow_request_accepts_enabled, true)
  })

  it("respects explicit false values from the database", () => {
    const prefs = mapNotificationPreferencesRow(
      {
        user_id: "user-1",
        notifications_enabled: true,
        story_replies_enabled: false,
        shares_enabled: false,
        product_updates_enabled: false,
      },
      "user-1"
    )
    assert.equal(prefs.story_replies_enabled, false)
    assert.equal(prefs.shares_enabled, false)
    assert.equal(prefs.product_updates_enabled, false)
    assert.equal(
      isNotificationPreferenceEnabled(prefs, "story_replies_enabled"),
      false
    )
  })
})
