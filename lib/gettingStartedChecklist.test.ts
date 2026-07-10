const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const { computeGettingStartedProgress, detectNewlyCompletedTasks } = require("./gettingStartedChecklist.ts")

const EMPTY = {
  onboardingCompleted: false,
  accountCount: 0,
  tradeCount: 0,
  hasRunAiAnalysis: false,
  hasEverJoinedOtherRoom: false,
}

function itemComplete(
  progress: ReturnType<typeof computeGettingStartedProgress>,
  id: string
) {
  return progress.items.find((i: { id: string }) => i.id === id)?.complete
}

describe("computeGettingStartedProgress", () => {
  it("orders profile first in the checklist", () => {
    const p = computeGettingStartedProgress(EMPTY)
    assert.equal(p.items[0]?.id, "profile")
    assert.equal(p.items[0]?.label, "Complete your profile")
    assert.equal(p.totalCount, 5)
  })

  it("profile task completes when onboarding is finished", () => {
    const p = computeGettingStartedProgress({
      ...EMPTY,
      onboardingCompleted: true,
    })
    assert.equal(itemComplete(p, "profile"), true)
    assert.equal(p.completedCount, 1)
  })

  it("account task completes when user has a trading account", () => {
    const p = computeGettingStartedProgress({ ...EMPTY, accountCount: 1 })
    assert.equal(itemComplete(p, "account"), true)
    assert.equal(itemComplete(p, "profile"), false)
    assert.equal(p.completedCount, 1)
  })

  it("trade task completes on first trade", () => {
    const p = computeGettingStartedProgress({ ...EMPTY, tradeCount: 1 })
    assert.equal(itemComplete(p, "trade"), true)
    assert.equal(p.completedCount, 1)
  })

  it("ai analysis task completes when analysis has run", () => {
    const p = computeGettingStartedProgress({
      ...EMPTY,
      hasRunAiAnalysis: true,
    })
    assert.equal(itemComplete(p, "ai_analysis"), true)
    assert.equal(p.completedCount, 1)
  })

  it("room task completes when user joined another room", () => {
    const p = computeGettingStartedProgress({
      ...EMPTY,
      hasEverJoinedOtherRoom: true,
    })
    assert.equal(itemComplete(p, "room"), true)
    assert.equal(p.completedCount, 1)
  })

  it("all five tasks complete at 5/5", () => {
    const p = computeGettingStartedProgress({
      onboardingCompleted: true,
      accountCount: 1,
      tradeCount: 3,
      hasRunAiAnalysis: true,
      hasEverJoinedOtherRoom: true,
    })
    assert.equal(p.completedCount, 5)
    assert.equal(p.totalCount, 5)
    assert.equal(p.allComplete, true)
  })

  it("detects newly completed tasks between snapshots", () => {
    const before = computeGettingStartedProgress(EMPTY)
    const after = computeGettingStartedProgress({ ...EMPTY, tradeCount: 1 })
    const newly = detectNewlyCompletedTasks(before, after)
    assert.equal(newly.length, 1)
    assert.equal(newly[0].id, "trade")
    assert.equal(newly[0].label, "Add your first trade")
  })
})

describe("getting started visibility", () => {
  const {
    shouldAutoShowGettingStartedChecklist,
    shouldOfferGettingStartedChecklist,
    shouldShowGettingStartedIntroPopup,
  } = require("./gettingStartedChecklist.ts")

  it("offers manual checklist while tasks remain", () => {
    assert.equal(
      shouldOfferGettingStartedChecklist("user-1", {
        hasSeenOnboardingCompletePopup: false,
        allComplete: false,
      }),
      true
    )
    assert.equal(
      shouldOfferGettingStartedChecklist("user-1", {
        hasSeenOnboardingCompletePopup: true,
        allComplete: false,
      }),
      false
    )
  })

  it("auto-shows after profile onboarding while tasks remain", () => {
    assert.equal(
      shouldAutoShowGettingStartedChecklist("user-1", {
        onboardingCompleted: false,
      }),
      false
    )
    assert.equal(
      shouldAutoShowGettingStartedChecklist("user-1", {
        onboardingCompleted: true,
        allComplete: false,
        hasSeenOnboardingCompletePopup: false,
      }),
      true
    )
    assert.equal(
      shouldAutoShowGettingStartedChecklist("user-1", {
        onboardingCompleted: true,
        allComplete: true,
      }),
      false
    )
    assert.equal(
      shouldAutoShowGettingStartedChecklist("user-1", {
        onboardingCompleted: true,
        hasSeenOnboardingCompletePopup: true,
      }),
      false
    )
  })

  it("intro popup never auto-shows", () => {
    assert.equal(
      shouldShowGettingStartedIntroPopup({
        onboardingCompleted: false,
        hasSeenGettingStartedIntro: false,
      }),
      false
    )
    assert.equal(
      shouldShowGettingStartedIntroPopup({
        onboardingCompleted: true,
        hasSeenGettingStartedIntro: false,
      }),
      false
    )
  })
})

describe("applyStickyGettingStartedProgress", () => {
  const localStorageMock = new Map<string, string>()
  if (typeof globalThis.window === "undefined") {
    ;(globalThis as typeof globalThis & { window: Window }).window = {
      localStorage: {
        getItem: (key: string) => localStorageMock.get(key) ?? null,
        setItem: (key: string, value: string) => {
          localStorageMock.set(key, value)
        },
        removeItem: (key: string) => {
          localStorageMock.delete(key)
        },
      },
    } as unknown as Window
  }

  const {
    applyStickyGettingStartedProgress,
    writeStickyCompletedItemIds,
  } = require("./gettingStartedSticky.ts")
  const { computeGettingStartedProgress } = require("./gettingStartedChecklist.ts")

  const userId = "test-user-sticky"

  it("does not let stale sticky inflate a fresh account", () => {
    localStorageMock.clear()
    writeStickyCompletedItemIds(
      userId,
      new Set(["profile", "account", "trade", "ai_analysis", "room"])
    )

    const serverProgress = computeGettingStartedProgress({
      onboardingCompleted: true,
      accountCount: 0,
      tradeCount: 0,
      hasRunAiAnalysis: false,
      hasEverJoinedOtherRoom: false,
    })

    const merged = applyStickyGettingStartedProgress(serverProgress, userId)

    assert.equal(merged.completedCount, 1)
    assert.equal(merged.items.find((i) => i.id === "profile")?.complete, true)
    assert.equal(merged.items.find((i) => i.id === "trade")?.complete, false)
  })
})
