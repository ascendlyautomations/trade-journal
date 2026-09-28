import type { SupabaseClient } from "@supabase/supabase-js"
import { tradovateAuthedFetch } from "./tradovateApiClient.ts"
import { tradovatePerformanceSep2026ReconstructionFills } from "./tradovatePerformanceSep2026Fixture.ts"
import {
  extractReportDefinitionsFromResponse,
  type TradovateReportDefinitionSummary,
} from "./tradovateReportDefinitionsParse.ts"
import {
  buildTradovateDateRangeAccountReportParams,
  describeReportParamValue,
  parseTradovateAccountEntityId,
  type TradovateReportRequestParamJson,
} from "./tradovateReportRequestParams.ts"

export type { TradovateReportDefinitionSummary } from "./tradovateReportDefinitionsParse.ts"
export { extractReportDefinitionsFromResponse } from "./tradovateReportDefinitionsParse.ts"

const RPT_DEMO_BASE = "https://rpt-demo.tradovateapi.com"
const REPORT_POLL_MS = 2_000
const REPORT_POLL_MAX_ATTEMPTS = 45

export const TRADOVATE_REFERENCE_SEP2026_FILL_IDS = [
  ...new Set(
    tradovatePerformanceSep2026ReconstructionFills().map((f) => f.fillId)
  ),
]

type EntityRow = Record<string, unknown>

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : []
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

function accountIdOf(row: EntityRow): string | null {
  const raw = row.accountId
  if (raw == null) return null
  return String(raw).trim()
}

function timestampOf(row: EntityRow): string | null {
  const ts = row.timestamp
  return ts != null ? String(ts) : null
}

function fillIdOf(row: EntityRow): string | null {
  const raw = row.id
  if (raw == null) return null
  return String(raw).trim()
}

function windowFromTimestamps(timestamps: string[]): {
  earliest: string | null
  latest: string | null
} {
  let earliest: string | null = null
  let latest: string | null = null
  for (const ts of timestamps) {
    if (!earliest || ts < earliest) earliest = ts
    if (!latest || ts > latest) latest = ts
  }
  return { earliest, latest }
}

function unwrapSyncMessage(json: unknown): Record<string, unknown> {
  if (!json || typeof json !== "object") return {}
  const record = json as Record<string, unknown>
  if (record.d && typeof record.d === "object") {
    return record.d as Record<string, unknown>
  }
  return record
}

function boolOrNull(raw: unknown): boolean | null {
  return typeof raw === "boolean" ? raw : null
}

function strOrNull(raw: unknown): string | null {
  if (raw == null) return null
  const s = String(raw).trim()
  return s.length > 0 ? s : null
}

function extractSyncAccountDiagnostics(
  sync: Record<string, unknown>,
  requestedAccountId: string
): TradovateSyncAccountDiagnostic[] {
  const target = requestedAccountId.trim()
  return asArray(sync.accounts).map((row) => {
    const r = row as EntityRow
    const id = strOrNull(r.id)
    const name = strOrNull(r.name)
    const closed = boolOrNull(r.closed)
    return {
      id,
      name,
      userId: strOrNull(r.userId),
      accountType: strOrNull(r.accountType),
      marginAccountType: strOrNull(r.marginAccountType),
      legalStatus: strOrNull(r.legalStatus),
      closed,
      restricted: boolOrNull(r.restricted),
      readonly: boolOrNull(r.readonly),
      active: closed === null ? null : !closed,
      matchesRequestedAccountId:
        (id != null && id === target) ||
        (name != null && name === target) ||
        (name != null && name.endsWith(target)),
    }
  })
}

function resolveReportAccountEntityId(
  syncAccounts: TradovateSyncAccountDiagnostic[],
  requestedAccountId: string
): number | null {
  const target = requestedAccountId.trim()
  const matched =
    syncAccounts.find((a) => a.matchesRequestedAccountId) ??
    syncAccounts.find((a) => a.id === target)
  if (matched?.id) return parseTradovateAccountEntityId(matched.id)
  return parseTradovateAccountEntityId(target)
}

function mapParamsUsed(params: TradovateReportRequestParamJson[]): TradovateReportParamUsed[] {
  return params.map((p) => {
    const desc = describeReportParamValue(p.value)
    return {
      name: p.name,
      value: p.value,
      jsonType: desc.jsonType,
      jsonLiteral: desc.jsonLiteral,
    }
  })
}

function extractReportErrorText(fullText: string, json: unknown): string | null {
  if (json && typeof json === "object") {
    const r = json as Record<string, unknown>
    if (r.errorText != null) return String(r.errorText)
    if (r.error != null) return String(r.error)
    if (r.message != null && !r.reportId) return String(r.message)
  }
  const trimmed = fullText.trim()
  if (trimmed.startsWith("{") && trimmed.includes("errorText")) {
    try {
      const parsed = JSON.parse(trimmed) as Record<string, unknown>
      if (parsed.errorText != null) return String(parsed.errorText)
    } catch {
      /* ignore */
    }
  }
  return null
}

function looksLikeReportCsv(text: string): boolean {
  const first = text.split(/\r?\n/)[0]?.toLowerCase() ?? ""
  if (!first.includes(",")) return false
  return (
    first.includes("fill") ||
    first.includes("symbol") ||
    first.includes("order") ||
    first.includes("timestamp") ||
    first.includes("buyfillid")
  )
}

function findHeaderColumn(header: string[], ...candidates: string[]): string | null {
  const idx = columnIndex(header, ...candidates)
  return idx >= 0 ? header[idx]! : null
}

function uniqueNonEmpty(values: string[], limit = 8): string[] {
  const out: string[] = []
  const seen = new Set<string>()
  for (const v of values) {
    const t = v.trim()
    if (!t || seen.has(t)) continue
    seen.add(t)
    out.push(t)
    if (out.length >= limit) break
  }
  return out
}

function assessFillsReportLedgerFeed(columnNames: string[]): {
  canPopulateWithoutFillItems: boolean
  missingForParseTradovateFillRow: string[]
  notes: string[]
} {
  const lower = columnNames.map((c) => c.toLowerCase())
  const has = (...needles: string[]) =>
    needles.some((n) => lower.some((col) => col === n || col.includes(n)))

  const missing: string[] = []
  if (!has("fillid", "fill id", "id")) missing.push("fillId")
  if (!has("orderid", "order id")) missing.push("orderId")
  if (!has("contractid", "contract id")) missing.push("contractId")
  if (!has("timestamp", "filltime", "execution", "tradetime", "time")) missing.push("timestamp")
  if (!has("action", "side", "buy/sell", "b/s")) missing.push("action")
  if (!has("qty", "quantity", "size")) missing.push("qty")
  if (!has("price", "fillprice", "avgprice")) missing.push("price")

  const notes: string[] = []
  if (has("symbol", "contract")) {
    notes.push("Contract symbol present; contractId may require order/contract lookup if only symbol is exported.")
  }
  if (has("commission", "fee", "clearing", "exchange", "nfa")) {
    notes.push("Fee/commission columns present; may map to fill fee enrichment without fill/items.")
  }

  return {
    canPopulateWithoutFillItems: missing.length === 0,
    missingForParseTradovateFillRow: missing,
    notes,
  }
}

export type TradovateSyncAccountDiagnostic = {
  id: string | null
  name: string | null
  userId: string | null
  accountType: string | null
  marginAccountType: string | null
  legalStatus: string | null
  closed: boolean | null
  restricted: boolean | null
  readonly: boolean | null
  active: boolean | null
  matchesRequestedAccountId: boolean
}

export type TradovateSyncRequestProbeResult = {
  httpStatus: number
  category: string
  ok: boolean
  textSnippet: string
  syncRequestBody: { users: number[] }
  syncMessageKeys: string[]
  counts: Record<string, number>
  accountsFromSync: TradovateSyncAccountDiagnostic[]
  requestedAccountPresentInSync: boolean
  reportAccountEntityIdUsed: number | null
  accountScoped: {
    fills: { count: number; earliest: string | null; latest: string | null }
    orders: { count: number; earliest: string | null; latest: string | null }
    executionReports: { count: number; earliest: string | null; latest: string | null }
    fillPairs: { count: number }
    positions: { count: number }
    cashBalances: { count: number }
  }
  referenceFillIdCount: number
  referenceFillIdsPresent: string[]
  referenceFillIdsMissing: string[]
  referenceFillIdsPresentCount: number
}

export type TradovateReportParamUsed = {
  name: string
  value: string | number
  jsonType: "string" | "number"
  jsonLiteral: string
}

export type TradovateCsvReportProbeResult = {
  httpStatus: number
  category: string
  ok: boolean
  reportCompleted: boolean
  reportName: string
  paramsUsed: TradovateReportParamUsed[]
  priorEncodingIssue?: string
  errorText: string | null
  responseFormat: string
  rowCount: number
  columnNames: string[]
  referenceFillIdCount: number
  referenceFillIdsFoundInCsv: string[]
  referenceFillIdsFoundCount: number
  workflow: {
    requestReportHttpStatus: number
    reportId: string | null
    pollAttempts: number
    getReportHttpStatus: number | null
    completionHint: string | null
  }
  textSnippet: string
}

export type TradovatePerformanceReportProbeResult = TradovateCsvReportProbeResult & {
  hasBuyFillId: boolean
  hasSellFillId: boolean
  earliestTradeTimestamp: string | null
  latestTradeTimestamp: string | null
  totalPnlSum: number | null
}

export type TradovateFillsReportProbeResult = TradovateCsvReportProbeResult & {
  earliestExecutionTimestamp: string | null
  latestExecutionTimestamp: string | null
  accountIdColumn: string | null
  fillIdColumn: string | null
  orderIdColumn: string | null
  contractIdColumn: string | null
  contractSymbolColumn: string | null
  sideOrActionColumn: string | null
  quantityColumn: string | null
  priceColumn: string | null
  timestampColumn: string | null
  feeOrCommissionColumns: string[]
  sampleAccountValuesInRows: string[]
  ledgerDirectFeedAssessment: {
    canPopulateWithoutFillItems: boolean
    missingForParseTradovateFillRow: string[]
    notes: string[]
  }
}

export type TradovateReportingProbeResult = {
  accountEncoding: {
    requestedAccountId: string
    reportAccountEntityId: number | null
    accountsParamRule: string
    stringValueWouldParseAsIdZero: boolean
  }
  definitions: {
    httpStatus: number
    category: string
    ok: boolean
    textSnippet: string
    responseRootKeys: string[]
    reportNames: string[]
    performance?: TradovateReportDefinitionSummary
    fills?: TradovateReportDefinitionSummary
    orders?: TradovateReportDefinitionSummary
    orderDetails?: TradovateReportDefinitionSummary
  }
  performanceReport?: TradovatePerformanceReportProbeResult
  fillsReport?: TradovateFillsReportProbeResult
}

function parseCsvHeader(line: string): string[] {
  const out: string[] = []
  let cur = ""
  let inQuotes = false
  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i]!
    if (ch === '"') {
      inQuotes = !inQuotes
      continue
    }
    if (ch === "," && !inQuotes) {
      out.push(cur.trim())
      cur = ""
      continue
    }
    cur += ch
  }
  out.push(cur.trim())
  return out
}

function parseCsvRows(csvText: string): { header: string[]; rows: string[][] } {
  const lines = csvText.split(/\r?\n/).filter((line) => line.trim().length > 0)
  if (lines.length === 0) return { header: [], rows: [] }
  const header = parseCsvHeader(lines[0]!)
  const rows = lines.slice(1).map((line) => parseCsvHeader(line))
  return { header, rows }
}

function columnIndex(header: string[], ...candidates: string[]): number {
  const lower = header.map((h) => h.toLowerCase())
  for (const c of candidates) {
    const idx = lower.indexOf(c.toLowerCase())
    if (idx >= 0) return idx
  }
  for (let i = 0; i < lower.length; i += 1) {
    for (const c of candidates) {
      if (lower[i]!.includes(c.toLowerCase())) return i
    }
  }
  return -1
}

function parseMoneyish(raw: string): number | null {
  const cleaned = raw.replace(/[$,\s"]/g, "").replace(/^\((.*)\)$/, "-$1")
  if (!cleaned) return null
  const n = Number(cleaned)
  return Number.isFinite(n) ? n : null
}

function extractReportId(json: unknown): string | null {
  if (!json || typeof json !== "object") return null
  const r = json as Record<string, unknown>
  for (const key of ["reportId", "id", "report_id"]) {
    if (r[key] != null) return String(r[key]).trim()
  }
  if (r.data && typeof r.data === "object") {
    const d = r.data as Record<string, unknown>
    if (d.reportId != null) return String(d.reportId).trim()
  }
  return null
}

function looksLikePerformanceCsv(text: string): boolean {
  return looksLikeReportCsv(text)
}

function resolveCsvFromFetch(fullText: string, json: unknown): string {
  if (fullText && looksLikePerformanceCsv(fullText)) return fullText
  if (typeof json === "string" && looksLikePerformanceCsv(json)) return json
  if (json && typeof json === "object") {
    const r = json as Record<string, unknown>
    for (const key of ["data", "csv", "report", "content", "body"]) {
      const val = r[key]
      if (typeof val === "string" && val.length > 0) return val
    }
  }
  return fullText
}

async function pollTradovateReportCsv(
  supabase: SupabaseClient,
  params: { userId: string; connectionId: string },
  reportId: string
): Promise<{ csv: string; getReportHttpStatus: number | null; pollAttempts: number; completionHint: string | null }> {
  let pollAttempts = 0
  let lastStatus: number | null = null
  let completionHint: string | null = null
  let csv = ""

  for (let i = 0; i < REPORT_POLL_MAX_ATTEMPTS; i += 1) {
    pollAttempts = i + 1
    const fetched = await tradovateAuthedFetch(
      supabase,
      params.userId,
      params.connectionId,
      `/v1/reports/getReport?reportId=${encodeURIComponent(reportId)}`,
      { method: "GET", baseUrlOverride: RPT_DEMO_BASE }
    )
    lastStatus = fetched.status
    csv = resolveCsvFromFetch(fetched.fullText, fetched.json)
    if (fetched.json && typeof fetched.json === "object") {
      const r = fetched.json as Record<string, unknown>
      if (r.status != null) completionHint = String(r.status)
      if (r.state != null) completionHint = String(r.state)
    }
    if (csv && looksLikePerformanceCsv(csv)) {
      return { csv, getReportHttpStatus: lastStatus, pollAttempts, completionHint }
    }
    if (fetched.ok && csv.length > 200 && csv.includes(",")) {
      return { csv, getReportHttpStatus: lastStatus, pollAttempts, completionHint }
    }
    await sleep(REPORT_POLL_MS)
  }

  return {
    csv,
    getReportHttpStatus: lastStatus,
    pollAttempts,
    completionHint: completionHint ?? "poll_timeout",
  }
}

async function requestTradovateCsvReport(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
    reportName: string
    reportParams: TradovateReportRequestParamJson[]
  }
): Promise<{
  reportFetch: Awaited<ReturnType<typeof tradovateAuthedFetch>>
  csvText: string
  reportId: string | null
  pollAttempts: number
  getReportHttpStatus: number | null
  completionHint: string | null
  errorText: string | null
}> {
  const reportBody = {
    name: params.reportName,
    representationType: "csv",
    timezone: -240,
    params: params.reportParams,
  }

  const reportFetch = await tradovateAuthedFetch(
    supabase,
    params.userId,
    params.connectionId,
    "/v1/reports/requestReport",
    {
      method: "POST",
      jsonBody: reportBody,
      baseUrlOverride: RPT_DEMO_BASE,
    }
  )

  let csvText = resolveCsvFromFetch(reportFetch.fullText, reportFetch.json)
  const reportId = extractReportId(reportFetch.json)
  let pollAttempts = 0
  let getReportHttpStatus: number | null = null
  let completionHint: string | null = null
  let errorText = extractReportErrorText(reportFetch.fullText, reportFetch.json)

  if ((!csvText || !looksLikeReportCsv(csvText)) && reportId && !errorText) {
    const polled = await pollTradovateReportCsv(
      supabase,
      { userId: params.userId, connectionId: params.connectionId },
      reportId
    )
    csvText = polled.csv
    pollAttempts = polled.pollAttempts
    getReportHttpStatus = polled.getReportHttpStatus
    completionHint = polled.completionHint
    if (!errorText && csvText.trim().startsWith("{")) {
      errorText = extractReportErrorText(csvText, null)
    }
  } else if (reportFetch.json && typeof reportFetch.json === "object") {
    const r = reportFetch.json as Record<string, unknown>
    if (r.status != null) completionHint = String(r.status)
  }

  if (!errorText && csvText.trim().startsWith("{")) {
    errorText = extractReportErrorText(csvText, null)
  }

  return {
    reportFetch,
    csvText,
    reportId,
    pollAttempts,
    getReportHttpStatus,
    completionHint,
    errorText,
  }
}

function countReferenceIdsInCsv(csvText: string, reference: readonly string[]): string[] {
  const found: string[] = []
  for (const fillId of reference) {
    if (csvText.includes(fillId)) found.push(fillId)
  }
  return found
}

export async function runTradovateSyncRequestProbe(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
    providerUserId: number
    accountId: string
    referenceFillIds?: readonly string[]
  }
): Promise<TradovateSyncRequestProbeResult> {
  const reference =
    params.referenceFillIds ?? TRADOVATE_REFERENCE_SEP2026_FILL_IDS
  const referenceSet = new Set(reference.map(String))

  const syncRequestBody = { users: [params.providerUserId] }

  const fetched = await tradovateAuthedFetch(
    supabase,
    params.userId,
    params.connectionId,
    "/v1/user/syncrequest",
    {
      method: "POST",
      jsonBody: syncRequestBody,
    }
  )

  const sync = unwrapSyncMessage(fetched.json)
  const keys = Object.keys(sync).sort()
  const counts: Record<string, number> = {}
  for (const key of keys) {
    counts[key] = asArray(sync[key]).length
  }

  const target = String(params.accountId).trim()
  const fills = asArray(sync.fills).filter(
    (row) => accountIdOf(row as EntityRow) === target
  ) as EntityRow[]
  const orders = asArray(sync.orders).filter(
    (row) => accountIdOf(row as EntityRow) === target
  ) as EntityRow[]
  const executionReports = asArray(sync.executionReports).filter(
    (row) => accountIdOf(row as EntityRow) === target
  ) as EntityRow[]
  const fillPairs = asArray(sync.fillPairs).filter((row) => {
    const r = row as EntityRow
    return accountIdOf(r) === target
  })
  const positions = asArray(sync.positions).filter(
    (row) => accountIdOf(row as EntityRow) === target
  )
  const cashBalances = asArray(sync.cashBalances).filter(
    (row) => accountIdOf(row as EntityRow) === target
  )

  const fillTimestamps = fills
    .map((f) => timestampOf(f))
    .filter((t): t is string => Boolean(t))
  const orderTimestamps = orders
    .map((o) => timestampOf(o))
    .filter((t): t is string => Boolean(t))
  const execTimestamps = executionReports
    .map((e) => timestampOf(e))
    .filter((t): t is string => Boolean(t))

  const fillIdsPresent = fills
    .map((f) => fillIdOf(f))
    .filter((id): id is string => Boolean(id))
  const referencePresent = fillIdsPresent.filter((id) => referenceSet.has(id))
  const referenceMissing = reference.filter((id) => !referencePresent.includes(id))

  const accountsFromSync = extractSyncAccountDiagnostics(sync, target)
  const reportAccountEntityIdUsed = resolveReportAccountEntityId(accountsFromSync, target)
  const requestedAccountPresentInSync = accountsFromSync.some((a) => a.matchesRequestedAccountId)

  return {
    httpStatus: fetched.status,
    category: fetched.category,
    ok: fetched.ok,
    textSnippet: fetched.textSnippet,
    syncRequestBody,
    syncMessageKeys: keys,
    counts,
    accountsFromSync,
    requestedAccountPresentInSync,
    reportAccountEntityIdUsed,
    accountScoped: {
      fills: { count: fills.length, ...windowFromTimestamps(fillTimestamps) },
      orders: { count: orders.length, ...windowFromTimestamps(orderTimestamps) },
      executionReports: {
        count: executionReports.length,
        ...windowFromTimestamps(execTimestamps),
      },
      fillPairs: { count: fillPairs.length },
      positions: { count: positions.length },
      cashBalances: { count: cashBalances.length },
    },
    referenceFillIdCount: reference.length,
    referenceFillIdsPresent: referencePresent,
    referenceFillIdsMissing: referenceMissing,
    referenceFillIdsPresentCount: referencePresent.length,
  }
}

export async function runTradovateReportingProbe(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
    accountId: string
    startDate: string
    endDate: string
    referenceFillIds?: readonly string[]
    reportAccountEntityId?: number | null
    syncAccounts?: TradovateSyncAccountDiagnostic[]
  }
): Promise<TradovateReportingProbeResult> {
  const reference =
    params.referenceFillIds ?? TRADOVATE_REFERENCE_SEP2026_FILL_IDS

  let definitionsFetch = await tradovateAuthedFetch(
    supabase,
    params.userId,
    params.connectionId,
    "/v1/reports/requestReportDefinitions",
    { method: "GET", baseUrlOverride: RPT_DEMO_BASE }
  )
  if (definitionsFetch.status === 405 || definitionsFetch.status === 404) {
    definitionsFetch = await tradovateAuthedFetch(
      supabase,
      params.userId,
      params.connectionId,
      "/v1/reports/requestReportDefinitions",
      { method: "POST", jsonBody: {}, baseUrlOverride: RPT_DEMO_BASE }
    )
  }

  const rootKeys =
    definitionsFetch.json && typeof definitionsFetch.json === "object"
      ? Object.keys(definitionsFetch.json as Record<string, unknown>).sort()
      : []

  const summaries = extractReportDefinitionsFromResponse(definitionsFetch.json)
  const reportNames = summaries.map((d) => d.name)
  const performance = summaries.find((d) => d.name === "Performance")
  const fills = summaries.find((d) => d.name === "Fills")
  const orders = summaries.find((d) => d.name === "Orders")
  const orderDetails = summaries.find((d) => d.name === "Order Details")

  const reportAccountEntityId =
    params.reportAccountEntityId ??
    (params.syncAccounts
      ? resolveReportAccountEntityId(params.syncAccounts, params.accountId)
      : parseTradovateAccountEntityId(params.accountId))

  const result: TradovateReportingProbeResult = {
    accountEncoding: {
      requestedAccountId: params.accountId,
      reportAccountEntityId,
      accountsParamRule:
        'param name "account", paramType "accounts": JSON number account entity id (not a string)',
      stringValueWouldParseAsIdZero: true,
    },
    definitions: {
      httpStatus: definitionsFetch.status,
      category: definitionsFetch.category,
      ok: definitionsFetch.ok,
      textSnippet: definitionsFetch.textSnippet,
      responseRootKeys: rootKeys,
      reportNames,
      performance,
      fills,
      orders,
      orderDetails,
    },
  }

  if (!definitionsFetch.ok || reportAccountEntityId == null) {
    return result
  }

  const reportParams = buildTradovateDateRangeAccountReportParams({
    startDate: params.startDate,
    endDate: params.endDate,
    accountEntityId: reportAccountEntityId,
  })
  const paramsUsed = mapParamsUsed(reportParams)

  if (performance) {
    const perf = await requestTradovateCsvReport(supabase, {
      userId: params.userId,
      connectionId: params.connectionId,
      reportName: "Performance",
      reportParams,
    })

    const { header: columnNames, rows } = parseCsvRows(perf.csvText)
    const rowCount = rows.length
    const lowerCols = columnNames.map((c) => c.toLowerCase())
    const hasBuyFillId = lowerCols.some((c) => c.includes("buyfillid"))
    const hasSellFillId = lowerCols.some((c) => c.includes("sellfillid"))
    const referenceFound = countReferenceIdsInCsv(perf.csvText, reference)

    const boughtIdx = columnIndex(columnNames, "boughttimestamp", "buytimestamp")
    const soldIdx = columnIndex(columnNames, "soldtimestamp", "selltimestamp")
    const pnlIdx = columnIndex(columnNames, "pnl", "realizedpnl", "profit")

    const tradeTimestamps: string[] = []
    let totalPnlSum = 0
    let pnlCount = 0
    for (const row of rows) {
      if (boughtIdx >= 0 && row[boughtIdx]) tradeTimestamps.push(row[boughtIdx]!)
      if (soldIdx >= 0 && row[soldIdx]) tradeTimestamps.push(row[soldIdx]!)
      if (pnlIdx >= 0 && row[pnlIdx]) {
        const pnl = parseMoneyish(row[pnlIdx]!)
        if (pnl != null) {
          totalPnlSum += pnl
          pnlCount += 1
        }
      }
    }
    const tradeWindow = windowFromTimestamps(tradeTimestamps)
    const reportCompleted = perf.errorText == null && rowCount > 0

    result.performanceReport = {
      httpStatus: perf.reportFetch.status,
      category: perf.reportFetch.category,
      ok: perf.reportFetch.ok && reportCompleted,
      reportCompleted,
      reportName: "Performance",
      paramsUsed,
      priorEncodingIssue:
        'Sending `"value":"65788591"` (string) yields errorText account is not found (ID:0); use JSON number.',
      errorText: perf.errorText,
      responseFormat: looksLikePerformanceCsv(perf.csvText) ? "csv" : "unknown",
      rowCount,
      columnNames,
      hasBuyFillId,
      hasSellFillId,
      referenceFillIdCount: reference.length,
      referenceFillIdsFoundInCsv: referenceFound,
      referenceFillIdsFoundCount: referenceFound.length,
      earliestTradeTimestamp: tradeWindow.earliest,
      latestTradeTimestamp: tradeWindow.latest,
      totalPnlSum: pnlCount > 0 ? totalPnlSum : null,
      workflow: {
        requestReportHttpStatus: perf.reportFetch.status,
        reportId: perf.reportId,
        pollAttempts: perf.pollAttempts,
        getReportHttpStatus: perf.getReportHttpStatus,
        completionHint: perf.completionHint,
      },
      textSnippet: perf.csvText.slice(0, 280).replace(/\s+/g, " "),
    }
  }

  if (fills) {
    const fillsRun = await requestTradovateCsvReport(supabase, {
      userId: params.userId,
      connectionId: params.connectionId,
      reportName: "Fills",
      reportParams,
    })

    const { header: columnNames, rows } = parseCsvRows(fillsRun.csvText)
    const rowCount = rows.length
    const referenceFound = countReferenceIdsInCsv(fillsRun.csvText, reference)

    const fillIdColumn = findHeaderColumn(
      columnNames,
      "fillid",
      "fill id",
      "id"
    )
    const orderIdColumn = findHeaderColumn(columnNames, "orderid", "order id")
    const contractIdColumn = findHeaderColumn(columnNames, "contractid", "contract id")
    const contractSymbolColumn = findHeaderColumn(
      columnNames,
      "symbol",
      "contract",
      "product"
    )
    const sideOrActionColumn = findHeaderColumn(
      columnNames,
      "action",
      "side",
      "b/s",
      "buy/sell"
    )
    const quantityColumn = findHeaderColumn(columnNames, "qty", "quantity", "size")
    const priceColumn = findHeaderColumn(columnNames, "price", "fillprice", "avgprice")
    const timestampColumn = findHeaderColumn(
      columnNames,
      "timestamp",
      "filltime",
      "executiontime",
      "tradetime",
      "time"
    )
    const accountIdColumn = findHeaderColumn(
      columnNames,
      "accountid",
      "account id",
      "account"
    )

    const feeOrCommissionColumns = columnNames.filter((c) => {
      const l = c.toLowerCase()
      return (
        l.includes("commission") ||
        l.includes("fee") ||
        l.includes("clearing") ||
        l.includes("exchange") ||
        l.includes("nfa")
      )
    })

    const tsIdx = timestampColumn ? columnIndex(columnNames, timestampColumn) : -1
    const execTimestamps: string[] = []
    if (tsIdx >= 0) {
      for (const row of rows) {
        if (row[tsIdx]) execTimestamps.push(row[tsIdx]!)
      }
    }
    const execWindow = windowFromTimestamps(execTimestamps)

    const acctIdx = accountIdColumn ? columnIndex(columnNames, accountIdColumn) : -1
    const sampleAccountValuesInRows =
      acctIdx >= 0
        ? uniqueNonEmpty(rows.map((row) => row[acctIdx] ?? ""))
        : []

    const ledgerDirectFeedAssessment = assessFillsReportLedgerFeed(columnNames)
    const reportCompleted = fillsRun.errorText == null && rowCount > 0

    result.fillsReport = {
      httpStatus: fillsRun.reportFetch.status,
      category: fillsRun.reportFetch.category,
      ok: fillsRun.reportFetch.ok && reportCompleted,
      reportCompleted,
      reportName: "Fills",
      paramsUsed,
      errorText: fillsRun.errorText,
      responseFormat: looksLikeReportCsv(fillsRun.csvText) ? "csv" : "unknown",
      rowCount,
      columnNames,
      referenceFillIdCount: reference.length,
      referenceFillIdsFoundInCsv: referenceFound,
      referenceFillIdsFoundCount: referenceFound.length,
      earliestExecutionTimestamp: execWindow.earliest,
      latestExecutionTimestamp: execWindow.latest,
      accountIdColumn,
      fillIdColumn,
      orderIdColumn,
      contractIdColumn,
      contractSymbolColumn,
      sideOrActionColumn,
      quantityColumn,
      priceColumn,
      timestampColumn,
      feeOrCommissionColumns,
      sampleAccountValuesInRows,
      ledgerDirectFeedAssessment,
      workflow: {
        requestReportHttpStatus: fillsRun.reportFetch.status,
        reportId: fillsRun.reportId,
        pollAttempts: fillsRun.pollAttempts,
        getReportHttpStatus: fillsRun.getReportHttpStatus,
        completionHint: fillsRun.completionHint,
      },
      textSnippet: fillsRun.csvText.slice(0, 280).replace(/\s+/g, " "),
    }
  }

  return result
}
