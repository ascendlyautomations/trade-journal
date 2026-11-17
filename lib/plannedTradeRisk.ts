/** Optional planned dollar risk at entry (`trades.dollar_risk`). Never derived from P&L or R:R. */

export function parseOptionalPlannedDollarRisk(
  raw: string
): number | null | "invalid" {
  const trimmed = raw.trim().replace(/[$,\s]/g, "")
  if (!trimmed) return null
  const value = Number(trimmed)
  if (!Number.isFinite(value) || value <= 0) return "invalid"
  return value
}

export function plannedDollarRiskForSave(
  raw: string
): number | null | "invalid" {
  return parseOptionalPlannedDollarRisk(raw)
}

/** Positive stored `trades.dollar_risk` only — never inferred from other fields. */
export function storedPlannedDollarRisk(value: unknown): number | null {
  if (value == null || value === "") return null
  const n = typeof value === "number" ? value : Number(value)
  if (!Number.isFinite(n) || n <= 0) return null
  return n
}
