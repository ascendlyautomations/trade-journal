const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  isCommentNotificationAllowed,
  mapNotificationPreferencesRow,
} = require("./notificationPreferences.ts")

describe("notification preferences", () => {
  const base = mapNotificationPreferencesRow(null, "user-1")

  it("master toggle disables delivery checks", () => {
    const prefs = { ...base, notifications_enabled: false, likes_enabled: true }
    assert.equal(isCommentNotificationAllowed(prefs, "comment", false), false)
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
})
