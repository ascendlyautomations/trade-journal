const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const { computeGettingStartedProgress } = require("./gettingStartedChecklist.ts")

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

  it("profile task uses onboarding_completed only", () => {
    const incomplete = computeGettingStartedProgress({
      ...EMPTY,
      tradeCount: 5,
      onboardingCompleted: false,
    })
    assert.equal(itemComplete(incomplete, "profile"), false)

    const complete = computeGettingStartedProgress({
      ...EMPTY,
      onboardingCompleted: true,
    })
    assert.equal(itemComplete(complete, "profile"), true)
  })
})
