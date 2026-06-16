/**
 * Simulates the baseline-race that swallowed first-trade popups.
 * Run: node scripts/simulate-getting-started-race.mjs
 */

function computeProgress(signals) {
  const items = [
    { id: "profile", complete: signals.onboardingCompleted },
    { id: "trade", complete: signals.tradeCount > 0 },
    { id: "post", complete: signals.profilePostCount > 0 },
    { id: "follow", complete: signals.followCount > 0 },
    { id: "room", complete: signals.hasEverJoinedOtherRoom },
    { id: "public", complete: signals.hasPublicTrade },
  ]
  const completedCount = items.filter((i) => i.complete).length
  return { items, completedCount, totalCount: 6, allComplete: completedCount === 6 }
}

function detectNewlyCompleted(previous, next) {
  const newly = []
  for (const item of next.items) {
    const prior = previous.items.find((row) => row.id === item.id)
    if (item.complete && !prior?.complete) newly.push(item)
  }
  return newly
}

const EMPTY = {
  onboardingCompleted: false,
  tradeCount: 0,
  profilePostCount: 0,
  followCount: 0,
  hasEverJoinedOtherRoom: false,
  hasPublicTrade: false,
}

const shown = new Set()

function oldBaselinePath(fetchResult) {
  const progress = computeProgress(fetchResult)
  for (const item of progress.items) {
    if (item.complete) shown.add(item.id)
  }
  return { stepPopups: 0, reason: "baseline ack all complete" }
}

function oldTransitionPath(signalsRef, fetchResult) {
  const snapshot = computeProgress(signalsRef)
  const progress = computeProgress(fetchResult)
  const newly = detectNewlyCompleted(snapshot, progress).filter((i) => !shown.has(i.id))
  return { stepPopups: newly.length, tasks: newly.map((i) => i.id) }
}

function newPath({ baselineResolved, fromUserAction, signalsRef, fetchResult }) {
  const preFetch = computeProgress(signalsRef)
  const progress = computeProgress(fetchResult)
  const isBaseline = !baselineResolved

  if (isBaseline) {
    if (fromUserAction) {
      const newly = detectNewlyCompleted(preFetch, progress).filter((i) => !shown.has(i.id))
      for (const id of newly) shown.add(id.id)
      return { stepPopups: newly.length, tasks: newly.map((i) => i.id), path: "baseline+action" }
    }
    for (const item of progress.items) {
      if (item.complete) shown.add(item.id)
    }
    return { stepPopups: 0, tasks: [], path: "baseline ack" }
  }

  const newly = detectNewlyCompleted(preFetch, progress).filter((i) => !shown.has(i.id))
  for (const id of newly) shown.add(id.id)
  return { stepPopups: newly.length, tasks: newly.map((i) => i.id), path: "transition" }
}

console.log("=== OLD: baseline fetch returns after trade save (single fetch wins) ===")
shown.clear()
const oldSingle = oldBaselinePath({ ...EMPTY, tradeCount: 1 })
console.log(oldSingle)

console.log("\n=== OLD: action refresh after baseline, sticky snapshot already trade complete ===")
shown.clear()
shown.add("trade") // baseline already acked
const oldAfter = oldTransitionPath(EMPTY, { ...EMPTY, tradeCount: 1 })
console.log(oldAfter)

console.log("\n=== NEW: action refresh during baseline (fromUserAction) ===")
shown.clear()
const fixed = newPath({
  baselineResolved: false,
  fromUserAction: true,
  signalsRef: EMPTY,
  fetchResult: { ...EMPTY, tradeCount: 1 },
})
console.log(fixed)

console.log("\n=== NEW: returning user initial load ===")
shown.clear()
const returning = newPath({
  baselineResolved: false,
  fromUserAction: false,
  signalsRef: EMPTY,
  fetchResult: {
    onboardingCompleted: true,
    tradeCount: 3,
    profilePostCount: 1,
    followCount: 1,
    hasEverJoinedOtherRoom: true,
    hasPublicTrade: true,
  },
})
console.log(returning)
