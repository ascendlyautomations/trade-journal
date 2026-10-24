export const EXPENSE_RECURRENCES = [
  { value: "weekly", label: "Weekly" },
  { value: "monthly", label: "Monthly" },
  { value: "yearly", label: "Yearly" },
] as const

export type ExpenseRecurrence = (typeof EXPENSE_RECURRENCES)[number]["value"]

const MAX_OCCURRENCES = 2000

export function isExpenseRecurrence(value: string): value is ExpenseRecurrence {
  return EXPENSE_RECURRENCES.some((item) => item.value === value)
}

export function expenseRecurrenceLabel(recurrence: ExpenseRecurrence | null | undefined): string | null {
  if (!recurrence) return null
  return EXPENSE_RECURRENCES.find((item) => item.value === recurrence)?.label ?? null
}

/** Dates from the anchor through `through`, inclusive. Later dates stay out until that day. */
export function occurrenceDates(
  start: string,
  recurrence: ExpenseRecurrence | null | undefined,
  through: string
): string[] {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(start) || !/^\d{4}-\d{2}-\d{2}$/.test(through)) return []
  if (start > through) return []
  if (!recurrence) return [start]
  const anchor = parseDay(start)
  const dates: string[] = []
  for (let index = 0; index < MAX_OCCURRENCES; index += 1) {
    const day = formatDay(shift(anchor, recurrence, index))
    if (day > through) break
    dates.push(day)
  }
  return dates
}

function shift(
  anchor: { year: number; month: number; day: number },
  recurrence: ExpenseRecurrence,
  index: number
): { year: number; month: number; day: number } {
  if (recurrence === "weekly") {
    const utc = Date.UTC(anchor.year, anchor.month - 1, anchor.day + index * 7)
    const date = new Date(utc)
    return {
      year: date.getUTCFullYear(),
      month: date.getUTCMonth() + 1,
      day: date.getUTCDate(),
    }
  }
  if (recurrence === "yearly") {
    const year = anchor.year + index
    return { year, month: anchor.month, day: Math.min(anchor.day, daysInMonth(year, anchor.month)) }
  }
  const zero = anchor.year * 12 + (anchor.month - 1) + index
  const year = Math.floor(zero / 12)
  const month = (zero % 12) + 1
  return { year, month, day: Math.min(anchor.day, daysInMonth(year, month)) }
}

function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate()
}

function parseDay(day: string): { year: number; month: number; day: number } {
  const [year, month, date] = day.split("-").map(Number)
  return { year, month, day: date }
}

function formatDay(parts: { year: number; month: number; day: number }): string {
  return `${parts.year}-${String(parts.month).padStart(2, "0")}-${String(parts.day).padStart(2, "0")}`
}
