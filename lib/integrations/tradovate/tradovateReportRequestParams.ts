/**
 * Tradovate Reporting API `requestReport` params are `{ name, value }` pairs.
 * paramType `accounts` serialization is NOT documented precisely in-repo; use
 * `buildPerformanceAccountEncodingVariants()` in probes to discover the shape.
 */

export type TradovateReportRequestParamJson = {
  name: string
  value: unknown
}

export type TradovateReportRequestBody = {
  name: string
  representationType: "csv"
  timezone: number
  params: TradovateReportRequestParamJson[]
}

export function parseTradovateAccountEntityId(
  raw: number | string
): number | null {
  const id =
    typeof raw === "number" ? raw : Number(String(raw).trim().replace(/,/g, ""))
  if (!Number.isFinite(id) || id <= 0) return null
  return Math.trunc(id)
}

export function buildTradovateReportRequestBody(input: {
  reportName: string
  params: TradovateReportRequestParamJson[]
  timezone?: number
}): TradovateReportRequestBody {
  return {
    name: input.reportName,
    representationType: "csv",
    timezone: input.timezone ?? -240,
    params: input.params,
  }
}

export function buildDateRangeParams(input: {
  startDate: string
  endDate: string
}): TradovateReportRequestParamJson[] {
  return [
    { name: "startDate", value: input.startDate },
    { name: "endDate", value: input.endDate },
  ]
}

/** Prior default probe encoding (numeric scalar) — not proven correct for Reporting API. */
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
    ...buildDateRangeParams({
      startDate: input.startDate,
      endDate: input.endDate,
    }),
    encodeTradovateAccountsReportParam(input.accountEntityId),
  ]
}

export type TradovatePerformanceAccountEncodingVariant = {
  encodingName: string
  description: string
  params: TradovateReportRequestParamJson[]
}

/**
 * Plausible `paramType: accounts` serializations for internal capability probes only.
 */
export function buildPerformanceAccountEncodingVariants(input: {
  startDate: string
  endDate: string
  accountEntityId: number
  accountName?: string | null
}): TradovatePerformanceAccountEncodingVariant[] {
  const { startDate, endDate, accountEntityId, accountName } = input
  const dates = buildDateRangeParams({ startDate, endDate })

  const variants: TradovatePerformanceAccountEncodingVariant[] = [
    {
      encodingName: "account_value_json_number",
      description: 'name "account", value: 65788591 (JSON number scalar)',
      params: [...dates, { name: "account", value: accountEntityId }],
    },
    {
      encodingName: "account_value_json_string",
      description: 'name "account", value: "65788591" (JSON string scalar)',
      params: [...dates, { name: "account", value: String(accountEntityId) }],
    },
    {
      encodingName: "account_value_json_number_array",
      description: 'name "account", value: [65788591] (JSON array of numbers)',
      params: [...dates, { name: "account", value: [accountEntityId] }],
    },
    {
      encodingName: "account_value_json_string_array",
      description: 'name "account", value: ["65788591"] (JSON array of strings)',
      params: [...dates, { name: "account", value: [String(accountEntityId)] }],
    },
    {
      encodingName: "account_value_object_id",
      description: 'name "account", value: {"id":65788591}',
      params: [...dates, { name: "account", value: { id: accountEntityId } }],
    },
    {
      encodingName: "account_value_object_id_array",
      description: 'name "account", value: [{"id":65788591}]',
      params: [
        ...dates,
        { name: "account", value: [{ id: accountEntityId }] },
      ],
    },
    {
      encodingName: "accounts_param_name_json_number_array",
      description: 'name "accounts", value: [65788591] (plural param name)',
      params: [...dates, { name: "accounts", value: [accountEntityId] }],
    },
    {
      encodingName: "accounts_param_name_json_number",
      description: 'name "accounts", value: 65788591',
      params: [...dates, { name: "accounts", value: accountEntityId }],
    },
    {
      encodingName: "account_value_stringified_json_array",
      description: 'name "account", value: "[65788591]" (string holding JSON array text)',
      params: [...dates, { name: "account", value: `[${accountEntityId}]` }],
    },
    {
      encodingName: "account_value_stringified_json_object",
      description: 'name "account", value: "{\\"id\\":65788591}"',
      params: [
        ...dates,
        { name: "account", value: JSON.stringify({ id: accountEntityId }) },
      ],
    },
  ]

  if (accountName) {
    variants.push({
      encodingName: "account_value_account_name_string",
      description: `name "account", value: account.name (${accountName})`,
      params: [...dates, { name: "account", value: accountName }],
    })
  }

  return variants
}

export function describeReportParamValue(value: unknown): {
  jsonType: string
  jsonLiteral: string
} {
  if (value === null) {
    return { jsonType: "null", jsonLiteral: "null" }
  }
  const t = typeof value
  if (t === "number" || t === "string" || t === "boolean") {
    return { jsonType: t, jsonLiteral: JSON.stringify(value) }
  }
  return { jsonType: t, jsonLiteral: JSON.stringify(value) }
}

export function sanitizeReportRequestBodyForLog(
  body: TradovateReportRequestBody
): TradovateReportRequestBody {
  return body
}

export function errorTextIndicatesAccountIdZero(errorText: string | null): boolean {
  if (!errorText) return false
  return /\(ID:\s*0\)/i.test(errorText) || /\bID:\s*0\b/i.test(errorText)
}
