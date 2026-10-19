import { todayCheckInDateKey } from "./dateKey.ts"
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
}

let todayCache: TodayCheckInCache | null = null
let recentCache: RecentCheckInsCache | null = null
const listeners = new Set<() => void>()

function notifyCheckInCaches(): void {
  for (const listener of listeners) listener()
}

export function subscribeCheckInCaches(listener: () => void): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
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
  if (
    checkIn &&
    recentCache &&
    recentCache.userId === userId &&
    checkIn.checkInDate >= recentCache.startDate &&
    checkIn.checkInDate <= recentCache.endDate
  ) {
    recentCache = {
      ...recentCache,
      checkIns: [
        checkIn,
        ...recentCache.checkIns.filter(
          (row) => row.checkInDate !== checkIn.checkInDate
        ),
      ],
    }
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
  return recentCache.checkIns
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
  checkIns: TraderDailyCheckIn[]
): void {
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
  recentCache = { userId, startDate, endDate, checkIns: next }

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

/** @internal */
export function resetTodayCheckInCacheForTests(): void {
  todayCache = null
  recentCache = null
  listeners.clear()
}
