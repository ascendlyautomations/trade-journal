import { describe, it } from "node:test"
import assert from "node:assert/strict"
import { getTradingDayKey } from "../formatDate.ts"
import {
  DAILY_CHECK_IN_DASHBOARD_HREF,
  DAILY_CHECK_IN_QUERY_PARAM,
  TRADER_DAILY_CHECK_IN_CONFLICT,
} from "./constants.ts"
import {
  readRecentCheckInsCache,
  readTodayCheckInCache,
  resetTodayCheckInCacheForTests,
  writeRecentCheckInsCache,
  writeTodayCheckInCache,
} from "./sessionCache.ts"
import {
  CHECK_IN_HISTORY_DAY_WINDOW,
  checkInDateKey,
  checkInHistoryStartDateKey,
  todayCheckInDateKey,
} from "./dateKey.ts"
import {
  draftFromCheckIn,
  emptyCheckInDraft,
  isElevatedStress,
  stressLabel,
  type TraderDailyCheckIn,
} from "./types.ts"
import {
  formatSleepHoursInput,
  isCompleteCheckIn,
  parseSleepHoursInput,
  validateCheckInDraft,
} from "./validation.ts"

function checkIn(overrides: Partial<TraderDailyCheckIn> = {}): TraderDailyCheckIn {
  return {
    id: "id",
    ownerProfileId: "user",
    checkInDate: "2026-09-02",
    sleepHours: 7.5,
    sleepQuality: 4,
    morningRating: 4,
    stressLevel: 2,
    energyLevel: 4,
    focusLevel: 4,
    notes: null,
    createdAt: "2026-09-02T12:00:00.000Z",
    updatedAt: "2026-09-02T12:00:00.000Z",
    ...overrides,
  }
}

describe("TraderDailyCheckInValidation", () => {
  it("rejects out-of-range ratings with the iOS copy", () => {
    const draft = emptyCheckInDraft("2026-09-02")
    draft.sleepHours = 7.5
    draft.stressLevel = 6
    assert.equal(validateCheckInDraft(draft), "Stress must be between 1 and 5.")
  })

  it("requires sleep hours", () => {
    const draft = emptyCheckInDraft("2026-09-02")
    assert.equal(
      validateCheckInDraft(draft),
      "Enter hours of sleep between 0 and 24."
    )
  })

  it("accepts decimal sleep hours", () => {
    const draft = emptyCheckInDraft("2026-09-02")
    draft.sleepHours = 7.5
    assert.equal(validateCheckInDraft(draft), null)
  })

  it("defaults ratings to 3 and leaves sleep empty", () => {
    const draft = emptyCheckInDraft("2026-09-02")
    assert.equal(draft.sleepHours, null)
    assert.equal(draft.sleepQuality, 3)
    assert.equal(draft.morningRating, 3)
    assert.equal(draft.stressLevel, 3)
    assert.equal(draft.energyLevel, 3)
    assert.equal(draft.focusLevel, 3)
    assert.equal(draft.notes, "")
  })

  it("requires every rating plus sleep hours for completeness", () => {
    assert.equal(
      isCompleteCheckIn(checkIn({ sleepHours: null })),
      false
    )
    assert.equal(isCompleteCheckIn(checkIn()), true)
  })
})

describe("TraderDailyCheckInStressScale", () => {
  it("keeps the corrected storage semantics (do not invert)", () => {
    assert.equal(stressLabel(1), "Calm")
    assert.equal(stressLabel(5), "Very Stressed")
    assert.equal(isElevatedStress(1), false)
    assert.equal(isElevatedStress(4), true)
    assert.equal(isElevatedStress(5), true)
  })
})

describe("check-in Eastern date key", () => {
  it("uses the America/New_York calendar date, not the 6PM trading-day rollover", () => {
    const afterSix = new Date("2026-09-02T22:30:00.000Z")
    assert.equal(checkInDateKey(afterSix), "2026-09-02")
    assert.equal(getTradingDayKey(afterSix), "2026-09-03")
    assert.notEqual(checkInDateKey(afterSix), getTradingDayKey(afterSix))
  })

  it("stays on the same Eastern calendar day before midnight", () => {
    const lateMorning = new Date("2026-09-02T05:30:00.000Z")
    assert.equal(checkInDateKey(lateMorning), "2026-09-02")
    assert.equal(todayCheckInDateKey(lateMorning), "2026-09-02")
  })

  it("rolls at Eastern midnight, not 18:00", () => {
    const justAfterMidnight = new Date("2026-09-03T04:15:00.000Z")
    assert.equal(checkInDateKey(justAfterMidnight), "2026-09-03")
  })
})

describe("sleep hours input", () => {
  it("parses one-decimal values and formats them back", () => {
    assert.equal(parseSleepHoursInput("7.5"), 7.5)
    assert.equal(parseSleepHoursInput(""), null)
    assert.equal(formatSleepHoursInput(7.5), "7.5")
    assert.equal(formatSleepHoursInput(8), "8")
  })
})

describe("Daily Check-In contract", () => {
  it("upserts on the same unique key as iOS", () => {
    assert.equal(TRADER_DAILY_CHECK_IN_CONFLICT, "user_id,check_in_date")
    assert.equal(DAILY_CHECK_IN_QUERY_PARAM, "checkIn")
    assert.equal(DAILY_CHECK_IN_DASHBOARD_HREF, "/dashboard?checkIn=1")
  })

  it("does not invert stress when seeding a draft from a stored row", () => {
    const draft = draftFromCheckIn(checkIn({ stressLevel: 1 }))
    assert.equal(draft.stressLevel, 1)
    assert.equal(stressLabel(draft.stressLevel), "Calm")
  })
})

describe("check-in session cache", () => {
  it("seeds the recent window when saving today before any bulk fetch", () => {
    resetTodayCheckInCacheForTests()
    const today = todayCheckInDateKey()
    const start = checkInHistoryStartDateKey(CHECK_IN_HISTORY_DAY_WINDOW)
    const saved = checkIn({ checkInDate: today, sleepHours: 8 })
    writeTodayCheckInCache("user", today, saved)
    const recent = readRecentCheckInsCache("user", start, today)
    assert.equal(recent?.length, 1)
    assert.equal(recent?.[0]?.checkInDate, today)
    resetTodayCheckInCacheForTests()
  })

  it("merges a saved today check-in into the recent window", () => {
    resetTodayCheckInCacheForTests()
    const today = todayCheckInDateKey()
    const start = checkInHistoryStartDateKey(CHECK_IN_HISTORY_DAY_WINDOW)
    const saved = checkIn({ checkInDate: today, sleepHours: 8 })
    writeRecentCheckInsCache("user", start, today, [
      checkIn({ checkInDate: "2026-09-29", sleepHours: 6 }),
    ])
    writeTodayCheckInCache("user", today, saved)
    const recent = readRecentCheckInsCache("user", start, today)
    assert.equal(recent?.[0]?.checkInDate, today)
    assert.equal(recent?.[0]?.sleepHours, 8)
    resetTodayCheckInCacheForTests()
  })

  it("does not let a stale range fetch replace a just-saved today row", () => {
    resetTodayCheckInCacheForTests()
    const today = todayCheckInDateKey()
    const start = checkInHistoryStartDateKey(CHECK_IN_HISTORY_DAY_WINDOW)
    const saved = checkIn({ checkInDate: today, sleepHours: 9 })
    writeTodayCheckInCache("user", today, saved)
    writeRecentCheckInsCache("user", start, today, [
      checkIn({ checkInDate: today, sleepHours: 6 }),
    ])
    assert.equal(readTodayCheckInCache("user", today)?.sleepHours, 9)
    const recent = readRecentCheckInsCache("user", start, today)
    assert.equal(recent?.[0]?.sleepHours, 9)
    resetTodayCheckInCacheForTests()
  })
})
