export const TRADER_TYPE_OPTIONS = ["Futures", "Options", "Investor"] as const

export type TraderType = (typeof TRADER_TYPE_OPTIONS)[number]

export function normalizeTraderType(raw: unknown): TraderType | "" {
  const s = String(raw ?? "").trim()
  if ((TRADER_TYPE_OPTIONS as readonly string[]).includes(s)) return s as TraderType
  return ""
}
