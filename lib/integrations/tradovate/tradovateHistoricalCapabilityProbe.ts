import type { SupabaseClient } from "@supabase/supabase-js"
import { tradovateAuthedFetch } from "./tradovateApiClient.ts"
import { tradovatePerformanceSep2026ReconstructionFills } from "./tradovatePerformanceSep2026Fixture.ts"

const RPT_DEMO_BASE = "https://rpt-demo.tradovateapi.com"

export const TRADOVATE_REFERENCE_SEP2026_FILL_IDS = [
  ...new Set(
    tradovatePerformanceSep2026ReconstructionFills().map((f) => f.fillId)
  ),
]

type EntityRow = Record<string, unknown>

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : []
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

export type TradovateSyncRequestProbeResult = {
  httpStatus: number
  category: string
  ok: boolean
  textSnippet: string
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
  referenceFillIdsPresent: string[]
  referenceFillIdsMissing: string[]
}

export type TradovateReportDefinitionSummary = {
  name: string
  description?: string
  params: Array<{ name: string; paramType?: string; optional?: boolean }>
}

export type TradovateReportingProbeResult = {
  definitions: {
    httpStatus: number
    category: string
    ok: boolean
    textSnippet: string
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
    referenceFillIdsFoundInCsv: string[]
    textSnippet: string
  }
}

function summarizeReportDefinition(raw: unknown): TradovateReportDefinitionSummary | undefined {
  if (!raw || typeof raw !== "object") return undefined
  const row = raw as Record<string, unknown>
  const name = row.name != null ? String(row.name) : ""
  if (!name) return undefined
  const paramsRaw = asArray(row.params)
  const params = paramsRaw.map((p) => {
    const pr = p as Record<string, unknown>
    return {
      name: pr.name != null ? String(pr.name) : "",
      paramType: pr.paramType != null ? String(pr.paramType) : undefined,
      optional: pr.optional === true,
    }
  })
  return {
    name,
    description: row.description != null ? String(row.description) : undefined,
    params,
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

  const fetched = await tradovateAuthedFetch(
    supabase,
    params.userId,
    params.connectionId,
    "/v1/user/syncrequest",
    {
      method: "POST",
      jsonBody: {
        users: [params.providerUserId],
        accounts: [Number(params.accountId)],
      },
    }
  )

  const sync = (fetched.json ?? {}) as Record<string, unknown>
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
    referenceFillIdsPresent: referencePresent,
    referenceFillIdsMissing: referenceMissing,
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

  const defsRaw = asArray(definitionsFetch.json)
  const summaries = defsRaw
    .map((d) => summarizeReportDefinition(d))
    .filter((d): d is TradovateReportDefinitionSummary => Boolean(d))
  const reportNames = summaries.map((d) => d.name)
  const performance = summaries.find((d) => d.name === "Performance")
  const orders = summaries.find((d) => d.name === "Orders")

  const result: TradovateReportingProbeResult = {
    definitions: {
      httpStatus: definitionsFetch.status,
      category: definitionsFetch.category,
      ok: definitionsFetch.ok,
      textSnippet: definitionsFetch.textSnippet,
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

  let csvText = reportFetch.fullText
  if (!csvText && typeof reportFetch.json === "string") {
    csvText = reportFetch.json
  }
  if (
    !csvText &&
    reportFetch.json &&
    typeof reportFetch.json === "object" &&
    "data" in (reportFetch.json as Record<string, unknown>)
  ) {
    csvText = String((reportFetch.json as Record<string, unknown>).data ?? "")
  }
  if (!csvText && reportFetch.json != null) {
    csvText = JSON.stringify(reportFetch.json)
  }

  const lines = csvText.split(/\r?\n/).filter((line) => line.trim().length > 0)
  const header = lines[0] ?? ""
  const columnNames = header ? parseCsvHeader(header) : []
  const rowCount = Math.max(0, lines.length - (header ? 1 : 0))
  const lowerCols = columnNames.map((c) => c.toLowerCase())
  const hasBuyFillId = lowerCols.some((c) => c.includes("buyfillid"))
  const hasSellFillId = lowerCols.some((c) => c.includes("sellfillid"))

  const referenceFound: string[] = []
  for (const fillId of reference) {
    if (csvText.includes(fillId)) referenceFound.push(fillId)
  }

  result.performanceReport = {
    httpStatus: reportFetch.status,
    category: reportFetch.category,
    ok: reportFetch.ok,
    reportName: "Performance",
    paramsUsed: reportParams,
    responseFormat:
      typeof reportFetch.json === "string" || header.includes(",")
        ? "csv"
        : typeof reportFetch.json,
    rowCount,
    columnNames,
    hasBuyFillId,
    hasSellFillId,
    referenceFillIdsFoundInCsv: referenceFound,
    textSnippet: csvText.slice(0, 280).replace(/\s+/g, " "),
  }

  return result
}
