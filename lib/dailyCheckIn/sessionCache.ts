import {
  CHECK_IN_HISTORY_DAY_WINDOW,
  checkInHistoryStartDateKey,
  todayCheckInDateKey,
} from "./dateKey.ts"
import type { TraderDailyCheckIn } from "./types.ts"

type TodayCheckInCache = {
  userId: string
  dateKey: string
  checkIn: TraderDailyCheckIn | null
}

type RecentCheckInsCache = {
  userId: string
  startDate: string
  endDate: string
  checkIns: TraderDailyCheckIn[]
  /** Set after an authenticated Supabase read (or a local save). */
  authVerified: boolean
}

let todayCache: TodayCheckInCache | null = null
let recentCache: RecentCheckInsCache | null = null
const listeners = new Set<() => void>()
const networkRefreshListeners = new Set<() => void>()

function notifyCheckInCaches(): void {
  for (const listener of listeners) listener()
}

function defaultRecentCheckInWindow(): { startDate: string; endDate: string } {
  const endDate = todayCheckInDateKey()
  return {
    startDate: checkInHistoryStartDateKey(CHECK_IN_HISTORY_DAY_WINDOW),
    endDate,
  }
}

/** Keeps dashboard psychology + history hooks in sync after a local save. */
function mergeCheckInIntoRecentCache(
  userId: string,
  checkIn: TraderDailyCheckIn
): void {
  const { startDate, endDate } = defaultRecentCheckInWindow()
  if (checkIn.checkInDate < startDate || checkIn.checkInDate > endDate) {
    return
  }

  const priorRows =
    recentCache?.userId === userId &&
    recentCache.startDate === startDate &&
    recentCache.endDate === endDate
      ? recentCache.checkIns
      : recentCache?.userId === userId
        ? recentCache.checkIns.filter(
            (row) =>
              row.checkInDate >= startDate && row.checkInDate <= endDate
          )
        : []

  recentCache = {
    userId,
    startDate,
    endDate,
    authVerified: true,
    checkIns: [
      checkIn,
      ...priorRows.filter((row) => row.checkInDate !== checkIn.checkInDate),
    ],
  }
}

export function subscribeCheckInCaches(listener: () => void): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

/** After a successful save — hooks refetch from Supabase to match server + RLS. */
export function requestDailyCheckInNetworkRefresh(): void {
  for (const listener of networkRefreshListeners) listener()
}

export function subscribeDailyCheckInNetworkRefresh(
  listener: () => void
): () => void {
  networkRefreshListeners.add(listener)
  return () => {
    networkRefreshListeners.delete(listener)
  }
}

export function mergeCheckInsByDatePreferNewer(
  primary: readonly TraderDailyCheckIn[],
  secondary: readonly TraderDailyCheckIn[]
): TraderDailyCheckIn[] {
  const byDate = new Map<string, TraderDailyCheckIn>()
  for (const row of primary) {
    byDate.set(row.checkInDate, row)
  }
  for (const row of secondary) {
    const existing = byDate.get(row.checkInDate)
    if (!existing || row.updatedAt > existing.updatedAt) {
      byDate.set(row.checkInDate, row)
    }
  }
  return [...byDate.values()].sort((a, b) =>
    b.checkInDate.localeCompare(a.checkInDate)
  )
}

export function readTodayCheckInCache(
  userId: string,
  dateKey: string
): TraderDailyCheckIn | null | undefined {
  if (!todayCache) return undefined
  if (todayCache.userId !== userId || todayCache.dateKey !== dateKey) {
    return undefined
  }
  return todayCache.checkIn
}

export function writeTodayCheckInCache(
  userId: string,
  dateKey: string,
  checkIn: TraderDailyCheckIn | null
): void {
  todayCache = { userId, dateKey, checkIn }
  if (checkIn) {
    mergeCheckInIntoRecentCache(userId, checkIn)
  } else if (recentCache?.userId === userId) {
    recentCache = {
      ...recentCache,
      checkIns: recentCache.checkIns.filter((row) => row.checkInDate !== dateKey),
    }
  }
  notifyCheckInCaches()
}

/** Local save — always merge into the recent window; sync today slot when dated today. */
export function upsertSavedCheckInInSessionCaches(
  userId: string,
  saved: TraderDailyCheckIn
): void {
  mergeCheckInIntoRecentCache(userId, saved)
  const today = todayCheckInDateKey()
  if (saved.checkInDate === today) {
    todayCache = { userId, dateKey: today, checkIn: saved }
  }
  notifyCheckInCaches()
}

export function readRecentCheckInsCache(
  userId: string,
  startDate: string,
  endDate: string
): TraderDailyCheckIn[] | undefined {
  if (!recentCache) return undefined
  if (
    recentCache.userId !== userId ||
    recentCache.startDate !== startDate ||
    recentCache.endDate !== endDate
  ) {
    return undefined
  }
  if (!recentCache.authVerified && recentCache.checkIns.length === 0) {
    return undefined
  }
  return recentCache.checkIns
}

export function isRecentCheckInsCacheAuthVerified(
  userId: string,
  startDate: string,
  endDate: string
): boolean {
  if (!recentCache) return false
  if (
    recentCache.userId !== userId ||
    recentCache.startDate !== startDate ||
    recentCache.endDate !== endDate
  ) {
    return false
  }
  return recentCache.authVerified
}

export function readTodayFromRecentCheckInsCache(
  userId: string,
  dateKey: string
): TraderDailyCheckIn | null | undefined {
  if (!recentCache || recentCache.userId !== userId) return undefined
  if (dateKey < recentCache.startDate || dateKey > recentCache.endDate) {
    return undefined
  }
  return recentCache.checkIns.find((row) => row.checkInDate === dateKey) ?? null
}

export function resolveTodayCheckInFromCaches(
  userId: string,
  dateKey: string
): TraderDailyCheckIn | null | undefined {
  const today = readTodayCheckInCache(userId, dateKey)
  if (today !== undefined) return today
  return readTodayFromRecentCheckInsCache(userId, dateKey)
}

export function writeRecentCheckInsCache(
  userId: string,
  startDate: string,
  endDate: string,
  checkIns: TraderDailyCheckIn[],
  options?: { authVerified?: boolean }
): void {
  const authVerified = options?.authVerified ?? true
  let next = checkIns
  if (
    todayCache?.userId === userId &&
    todayCache.checkIn &&
    todayCache.checkIn.checkInDate >= startDate &&
    todayCache.checkIn.checkInDate <= endDate
  ) {
    const saved = todayCache.checkIn
    next = [
      saved,
      ...checkIns.filter((row) => row.checkInDate !== saved.checkInDate),
    ]
  }
  recentCache = { userId, startDate, endDate, checkIns: next, authVerified }

  const today = todayCheckInDateKey()
  if (
    today >= startDate &&
    today <= endDate &&
    (todayCache == null ||
      todayCache.userId !== userId ||
      todayCache.dateKey !== today)
  ) {
    todayCache = {
      userId,
      dateKey: today,
      checkIn: next.find((row) => row.checkInDate === today) ?? null,
    }
  }
  notifyCheckInCaches()
}

export function clearTodayCheckInCache(): void {
  todayCache = null
}

/** Clears in-memory check-in caches (e.g. on sign-out or account switch). */
export function invalidateDailyCheckInSessionCache(): void {
  todayCache = null
  recentCache = null
  notifyCheckInCaches()
}

/** @internal */
export function resetTodayCheckInCacheForTests(): void {
  todayCache = null
  recentCache = null
  listeners.clear()
  networkRefreshListeners.clear()
}
