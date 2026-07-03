export const JOURNAL_STREAK_MILESTONES = [
  3, 5, 10, 20, 30, 50, 75, 100, 150, 250, 365,
] as const

export const POSTING_STREAK_MILESTONES = [
  3, 5, 10, 20, 30, 50, 75, 100,
] as const

export const WINNING_STREAK_MILESTONES = [
  5, 10, 15, 20, 25, 30, 40, 50,
] as const

export type StreakKind = "journal" | "posting" | "winning"

export type StreakStats = {
  current: number
  longest: number
  nextMilestone: number | null
  progressRatio: number
  unitLabel: string
}

export function toLocalDateKey(iso: string): string {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ""
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, "0")
  const day = String(d.getDate()).padStart(2, "0")
  return `${y}-${m}-${day}`
}

export function parseLocalDateKey(key: string): Date {
  const [y, m, d] = key.split("-").map(Number)
  return new Date(y, m - 1, d, 12, 0, 0, 0)
}

export function isWeekendLocal(date: Date): boolean {
  const day = date.getDay()
  return day === 0 || day === 6
}

export function nextWeekdayDateKey(key: string): string {
  const d = parseLocalDateKey(key)
  d.setDate(d.getDate() + 1)
  while (isWeekendLocal(d)) {
    d.setDate(d.getDate() + 1)
  }
  return toLocalDateKey(d.toISOString())
}

export function areConsecutiveWeekdays(a: string, b: string): boolean {
  return nextWeekdayDateKey(a) === b
}

export function resolveNextMilestone(
  current: number,
  milestones: readonly number[]
): number | null {
  for (const milestone of milestones) {
    if (current < milestone) return milestone
  }
  return null
}

export function streakProgressRatio(
  current: number,
  nextMilestone: number | null
): number {
  if (!nextMilestone || nextMilestone <= 0) return 1
  return Math.min(1, Math.max(0, current / nextMilestone))
}

export function buildStreakStats(
  current: number,
  longest: number,
  milestones: readonly number[],
  unitLabel: string
): StreakStats {
  const nextMilestone = resolveNextMilestone(current, milestones)
  return {
    current,
    longest,
    nextMilestone,
    progressRatio: streakProgressRatio(current, nextMilestone),
    unitLabel,
  }
}

/** Weekday-only activity streak — weekends are skipped and never break the streak. */
export function computeWeekdayActivityStreak(
  activeDateKeys: Iterable<string>,
  today = new Date()
): { current: number; longest: number } {
  const activeDays = new Set<string>()
  for (const key of activeDateKeys) {
    const trimmed = key.trim()
    if (!trimmed) continue
    const d = parseLocalDateKey(trimmed)
    if (Number.isNaN(d.getTime()) || isWeekendLocal(d)) continue
    activeDays.add(trimmed)
  }

  if (activeDays.size === 0) {
    return { current: 0, longest: 0 }
  }

  let current = 0
  const cursor = new Date(today)
  cursor.setHours(12, 0, 0, 0)
  while (isWeekendLocal(cursor)) {
    cursor.setDate(cursor.getDate() - 1)
  }

  for (let guard = 0; guard < 500; guard += 1) {
    const key = toLocalDateKey(cursor.toISOString())
    if (!activeDays.has(key)) break
    current += 1
    cursor.setDate(cursor.getDate() - 1)
    while (isWeekendLocal(cursor)) {
      cursor.setDate(cursor.getDate() - 1)
    }
  }

  const sortedWeekdays = [...activeDays].sort()
  let longest = 0
  let run = 0
  let prev: string | null = null

  for (const key of sortedWeekdays) {
    if (prev && areConsecutiveWeekdays(prev, key)) {
      run += 1
    } else {
      run = 1
    }
    if (run > longest) longest = run
    prev = key
  }

  return { current, longest }
}

function compareTradesChronological(
  a: {
    created_at?: string | null
    entry_time?: string | null
    exit_time?: string | null
  },
  b: {
    created_at?: string | null
    entry_time?: string | null
    exit_time?: string | null
  }
): number {
  const ta = new Date(
    a.entry_time?.trim() || a.exit_time?.trim() || a.created_at?.trim() || 0
  ).getTime()
  const tb = new Date(
    b.entry_time?.trim() || b.exit_time?.trim() || b.created_at?.trim() || 0
  ).getTime()
  return ta - tb
}

/** Consecutive winning trades; break-even does not reset or increment. */
export function computeWinningTradeStreak(
  trades: readonly {
    pnl?: unknown
    created_at?: string | null
    entry_time?: string | null
    exit_time?: string | null
  }[]
): { current: number; longest: number } {
  if (!trades.length) return { current: 0, longest: 0 }

  const sorted = [...trades].sort(compareTradesChronological)
  let longest = 0
  let run = 0

  for (const trade of sorted) {
    const pnl = Number(trade.pnl) || 0
    if (pnl > 0) {
      run += 1
      if (run > longest) longest = run
    } else if (pnl < 0) {
      run = 0
    }
  }

  let current = 0
  for (let i = sorted.length - 1; i >= 0; i -= 1) {
    const pnl = Number(sorted[i].pnl) || 0
    if (pnl > 0) {
      current += 1
    } else if (pnl < 0) {
      break
    }
  }

  return { current, longest }
}

export function collectJournalWeekdayKeys(
  trades: readonly {
    created_at?: string | null
    entry_time?: string | null
    exit_time?: string | null
    date?: string | null
  }[]
): string[] {
  const keys: string[] = []
  for (const trade of trades) {
    const source =
      trade.entry_time?.trim() ||
      trade.exit_time?.trim() ||
      trade.created_at?.trim() ||
      trade.date?.trim() ||
      ""
    if (!source) continue
    const key = toLocalDateKey(source)
    if (key) keys.push(key)
  }
  return keys
}

export function collectPostingWeekdayKeys(
  timestamps: readonly (string | null | undefined)[]
): string[] {
  const keys: string[] = []
  for (const ts of timestamps) {
    if (!ts?.trim()) continue
    const key = toLocalDateKey(ts)
    if (key) keys.push(key)
  }
  return keys
}
