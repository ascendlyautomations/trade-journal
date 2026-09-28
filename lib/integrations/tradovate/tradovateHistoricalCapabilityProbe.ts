import type { SupabaseClient } from "@supabase/supabase-js"
import { tradovateAuthedFetch } from "./tradovateApiClient.ts"
import { tradovatePerformanceSep2026ReconstructionFills } from "./tradovatePerformanceSep2026Fixture.ts"
import {
  extractReportDefinitionsFromResponse,
  type TradovateReportDefinitionSummary,
} from "./tradovateReportDefinitionsParse.ts"

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

export type TradovateSyncRequestProbeResult = {
  httpStatus: number
  category: string
  ok: boolean
  textSnippet: string
  syncRequestBody: { users: number[] }
  syncMessageKeys: string[]
  counts: Record<string, number>
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

export type TradovateReportingProbeResult = {
  definitions: {
    httpStatus: number
    category: string
    ok: boolean
    textSnippet: string
    responseRootKeys: string[]
    reportNames: string[]
    performance?: TradovateReportDefinitionSummary
    orders?: TradovateReportDefinitionSummary
  }
  performanceReport?: {
    httpStatus: number
    category: string
    ok: boolean
    reportName: string
    paramsUsed: Array<{ name: string; value: string }>
    responseFormat: string
    rowCount: number
    columnNames: string[]
    hasBuyFillId: boolean
    hasSellFillId: boolean
    referenceFillIdCount: number
    referenceFillIdsFoundInCsv: string[]
    referenceFillIdsFoundCount: number
    earliestTradeTimestamp: string | null
    latestTradeTimestamp: string | null
    totalPnlSum: number | null
    workflow: {
      requestReportHttpStatus: number
      reportId: string | null
      pollAttempts: number
      getReportHttpStatus: number | null
      completionHint: string | null
    }
    textSnippet: string
  }
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
  const first = text.split(/\r?\n/)[0]?.toLowerCase() ?? ""
  return (
    first.includes("buyfillid") ||
    first.includes("symbol") ||
    (first.includes("fill") && first.includes(","))
  )
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

  return {
    httpStatus: fetched.status,
    category: fetched.category,
    ok: fetched.ok,
    textSnippet: fetched.textSnippet,
    syncRequestBody,
    syncMessageKeys: keys,
    counts,
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
  const orders = summaries.find((d) => d.name === "Orders")

  const result: TradovateReportingProbeResult = {
    definitions: {
      httpStatus: definitionsFetch.status,
      category: definitionsFetch.category,
      ok: definitionsFetch.ok,
      textSnippet: definitionsFetch.textSnippet,
      responseRootKeys: rootKeys,
      reportNames,
      performance,
      orders,
    },
  }

  if (!definitionsFetch.ok || !performance) {
    return result
  }

  const reportParams = [
    { name: "startDate", value: params.startDate },
    { name: "endDate", value: params.endDate },
    { name: "account", value: params.accountId },
  ]

  const reportBody = {
    name: "Performance",
    representationType: "csv",
    timezone: -240,
    params: reportParams,
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

  if ((!csvText || !looksLikePerformanceCsv(csvText)) && reportId) {
    const polled = await pollTradovateReportCsv(supabase, params, reportId)
    csvText = polled.csv
    pollAttempts = polled.pollAttempts
    getReportHttpStatus = polled.getReportHttpStatus
    completionHint = polled.completionHint
  } else if (reportFetch.json && typeof reportFetch.json === "object") {
    const r = reportFetch.json as Record<string, unknown>
    if (r.status != null) completionHint = String(r.status)
  }

  const { header: columnNames, rows } = parseCsvRows(csvText)
  const rowCount = rows.length
  const lowerCols = columnNames.map((c) => c.toLowerCase())
  const hasBuyFillId = lowerCols.some((c) => c.includes("buyfillid"))
  const hasSellFillId = lowerCols.some((c) => c.includes("sellfillid"))

  const referenceFound: string[] = []
  for (const fillId of reference) {
    if (csvText.includes(fillId)) referenceFound.push(fillId)
  }

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

  result.performanceReport = {
    httpStatus: reportFetch.status,
    category: reportFetch.category,
    ok: reportFetch.ok && rowCount > 0,
    reportName: "Performance",
    paramsUsed: reportParams,
    responseFormat: looksLikePerformanceCsv(csvText) ? "csv" : "unknown",
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
      requestReportHttpStatus: reportFetch.status,
      reportId,
      pollAttempts,
      getReportHttpStatus,
      completionHint,
    },
    textSnippet: csvText.slice(0, 280).replace(/\s+/g, " "),
  }

  return result
}
