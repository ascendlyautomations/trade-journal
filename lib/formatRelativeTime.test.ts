const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  formatRelativeTime,
  formatSocialTimestamp,
  formatPostedTimestamp,
  getNotificationTimeSection,
} = require("./formatRelativeTime.ts")

describe("formatRelativeTime", () => {
  const now = new Date("2026-06-25T15:00:00.000Z")

  it("shows Just now for under 30 seconds", () => {
    const ts = new Date(now.getTime() - 15_000).toISOString()
    assert.equal(formatRelativeTime(ts, now), "Just now")
  })

  it("shows seconds after 30 seconds", () => {
    const ts = new Date(now.getTime() - 45_000).toISOString()
    assert.equal(formatRelativeTime(ts, now), "45 seconds ago")
  })

  it("shows minutes under one hour", () => {
    const ts = new Date(now.getTime() - 5 * 60_000).toISOString()
    assert.equal(formatRelativeTime(ts, now), "5 minutes ago")
  })

  it("shows hours under one day", () => {
    const ts = new Date(now.getTime() - 3 * 60 * 60_000).toISOString()
    assert.equal(formatRelativeTime(ts, now), "3 hours ago")
  })

  it("shows Yesterday between 24 and 47 hours", () => {
    const ts = new Date(now.getTime() - 30 * 60 * 60_000).toISOString()
    assert.equal(formatRelativeTime(ts, now), "Yesterday")
  })
})

describe("formatSocialTimestamp", () => {
  const now = new Date("2026-06-25T15:00:00.000Z")

  it("uses compact Just now under 30 seconds", () => {
    const ts = new Date(now.getTime() - 10_000).toISOString()
    assert.equal(formatSocialTimestamp(ts, now), "Just now")
  })

  it("uses compact minutes and hours", () => {
    const fiveMin = new Date(now.getTime() - 5 * 60_000).toISOString()
    assert.equal(formatSocialTimestamp(fiveMin, now), "5m")
    const threeHr = new Date(now.getTime() - 3 * 60 * 60_000).toISOString()
    assert.equal(formatSocialTimestamp(threeHr, now), "3h")
  })

  it("uses Yesterday instead of 1d", () => {
    const ts = new Date(now.getTime() - 30 * 60 * 60_000).toISOString()
    assert.equal(formatSocialTimestamp(ts, now), "Yesterday")
  })
})

describe("formatPostedTimestamp", () => {
  const now = new Date("2026-06-25T15:00:00.000Z")

  it("shows Just now under 30 seconds", () => {
    const ts = new Date(now.getTime() - 10_000).toISOString()
    assert.equal(formatPostedTimestamp(ts, now), "Just now")
  })

  it("shows minutes and hours with ago suffix", () => {
    const fiveMin = new Date(now.getTime() - 5 * 60_000).toISOString()
    assert.equal(formatPostedTimestamp(fiveMin, now), "5m ago")
    const threeHr = new Date(now.getTime() - 3 * 60 * 60_000).toISOString()
    assert.equal(formatPostedTimestamp(threeHr, now), "3h ago")
  })

  it("shows Yesterday and day counts", () => {
    const ts = new Date(now.getTime() - 30 * 60 * 60_000).toISOString()
    assert.equal(formatPostedTimestamp(ts, now), "Yesterday")
    const threeDays = new Date(now.getTime() - 3 * 24 * 60 * 60_000).toISOString()
    assert.equal(formatPostedTimestamp(threeDays, now), "3d ago")
  })
})

describe("getNotificationTimeSection", () => {
  const now = new Date("2026-06-25T15:00:00.000Z")

  it("classifies same EST day as today", () => {
    assert.equal(
      getNotificationTimeSection("2026-06-25T10:00:00.000Z", now),
      "today"
    )
  })

  it("classifies prior EST day as yesterday", () => {
    assert.equal(
      getNotificationTimeSection("2026-06-24T10:00:00.000Z", now),
      "yesterday"
    )
  })
})
