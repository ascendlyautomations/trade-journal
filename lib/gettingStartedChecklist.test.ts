const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const { computeGettingStartedProgress, detectNewlyCompletedTasks } = require("./gettingStartedChecklist.ts")

const EMPTY = {
  onboardingCompleted: false,
  tradeCount: 0,
  profilePostCount: 0,
  followCount: 0,
  hasEverJoinedOtherRoom: false,
  hasPublicTrade: false,
}

function itemComplete(
  progress: ReturnType<typeof computeGettingStartedProgress>,
  id: string
) {
  return progress.items.find((i: { id: string }) => i.id === id)?.complete
}

describe("computeGettingStartedProgress", () => {
  it("scenario A: first trade only completes trade task", () => {
    const p = computeGettingStartedProgress({ ...EMPTY, tradeCount: 1 })
    assert.equal(itemComplete(p, "trade"), true)
    assert.equal(itemComplete(p, "post"), false)
    assert.equal(itemComplete(p, "public"), false)
    assert.equal(p.completedCount, 1)
  })

  it("scenario B: public trade completes trade and public, not post", () => {
    const p = computeGettingStartedProgress({
      ...EMPTY,
      tradeCount: 1,
      hasPublicTrade: true,
    })
    assert.equal(itemComplete(p, "trade"), true)
    assert.equal(itemComplete(p, "public"), true)
    assert.equal(itemComplete(p, "post"), false)
    assert.equal(p.completedCount, 2)
  })

  it("scenario B: feed trade rows alone must not complete post task", () => {
    // Previously feedPostCount > 0 incorrectly completed post; profilePostCount only.
    const p = computeGettingStartedProgress({
      ...EMPTY,
      tradeCount: 1,
      hasPublicTrade: true,
      profilePostCount: 0,
    })
    assert.equal(itemComplete(p, "post"), false)
  })

  it("scenario C: profile post only completes post task", () => {
    const p = computeGettingStartedProgress({
      ...EMPTY,
      profilePostCount: 1,
    })
    assert.equal(itemComplete(p, "post"), true)
    assert.equal(itemComplete(p, "trade"), false)
    assert.equal(itemComplete(p, "public"), false)
    assert.equal(p.completedCount, 1)
  })

  it("scenario D: follow only completes follow task", () => {
    const p = computeGettingStartedProgress({ ...EMPTY, followCount: 1 })
    assert.equal(itemComplete(p, "follow"), true)
    assert.equal(itemComplete(p, "trade"), false)
    assert.equal(itemComplete(p, "post"), false)
    assert.equal(itemComplete(p, "public"), false)
    assert.equal(itemComplete(p, "room"), false)
    assert.equal(p.completedCount, 1)
  })

  it("scenario E: room join only completes room task", () => {
    const p = computeGettingStartedProgress({
      ...EMPTY,
      hasEverJoinedOtherRoom: true,
    })
    assert.equal(itemComplete(p, "room"), true)
    assert.equal(itemComplete(p, "follow"), false)
    assert.equal(p.completedCount, 1)
  })

  it("scenario F: all six tasks complete at 6/6", () => {
    const p = computeGettingStartedProgress({
      onboardingCompleted: true,
      tradeCount: 3,
      profilePostCount: 1,
      followCount: 2,
      hasEverJoinedOtherRoom: true,
      hasPublicTrade: true,
    })
    assert.equal(p.completedCount, 6)
    assert.equal(p.totalCount, 6)
    assert.equal(p.allComplete, true)
  })

  it("includes profile as the first checklist task", () => {
    const p = computeGettingStartedProgress(EMPTY)
    assert.equal(p.items[0]?.id, "profile")
    assert.equal(p.items[0]?.label, "Complete your profile")
    assert.equal(p.totalCount, 6)
  })

  it("profile task completes when onboarding is finished", () => {
    const p = computeGettingStartedProgress({
      ...EMPTY,
      onboardingCompleted: true,
    })
    assert.equal(itemComplete(p, "profile"), true)
    assert.equal(itemComplete(p, "trade"), false)
    assert.equal(p.completedCount, 1)
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

  it("does not let stale sticky inflate a fresh account to 5/6", () => {
    localStorageMock.clear()
    writeStickyCompletedItemIds(
      userId,
      new Set(["trade", "post", "follow", "room"])
    )

    const serverProgress = computeGettingStartedProgress({
      onboardingCompleted: true,
      tradeCount: 0,
      profilePostCount: 0,
      followCount: 0,
      hasEverJoinedOtherRoom: false,
      hasPublicTrade: false,
    })

    const merged = applyStickyGettingStartedProgress(serverProgress, userId, {
      profilePostCount: 0,
    })

    assert.equal(merged.completedCount, 1)
    assert.equal(merged.items.find((i) => i.id === "profile")?.complete, true)
    assert.equal(merged.items.find((i) => i.id === "trade")?.complete, false)
  })
})
