/**
 * Tradovate Reporting API `requestReport` params are `{ name, value }` pairs where
 * `value` must match the report definition's `paramType` (see partner docs + forum:
 * paramType `accounts` uses the account entity `id` as a JSON number, not a string).
 */

export type TradovateReportRequestParamJson = {
  name: string
  value: string | number
}

export function parseTradovateAccountEntityId(
  raw: number | string
): number | null {
  const id =
    typeof raw === "number" ? raw : Number(String(raw).trim().replace(/,/g, ""))
  if (!Number.isFinite(id) || id <= 0) return null
  return Math.trunc(id)
}

/**
 * Performance / Fills / Orders reports declare param name `account` with paramType `accounts`.
 */
export function encodeTradovateAccountsReportParam(
  accountEntityId: number | string
): TradovateReportRequestParamJson {
  const id = parseTradovateAccountEntityId(accountEntityId)
  if (id == null) {
    throw new Error(`invalid_tradovate_account_entity_id:${String(accountEntityId)}`)
  }
  return { name: "account", value: id }
}

export function buildTradovateDateRangeAccountReportParams(input: {
  startDate: string
  endDate: string
  accountEntityId: number | string
}): TradovateReportRequestParamJson[] {
  return [
    { name: "startDate", value: input.startDate },
    { name: "endDate", value: input.endDate },
    encodeTradovateAccountsReportParam(input.accountEntityId),
  ]
}

/** Document how a param serializes in JSON (for probe output). */
export function describeReportParamValue(value: string | number): {
  jsonType: "string" | "number"
  jsonLiteral: string
} {
  if (typeof value === "number") {
    return { jsonType: "number", jsonLiteral: String(value) }
  }
  return { jsonType: "string", jsonLiteral: JSON.stringify(value) }
}
