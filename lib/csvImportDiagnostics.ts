import {
  type BuildTradesFromParsedCsvResult,
  type CsvFileFormat,
  type CsvRow,
  type LogicalField,
  detectCsvFileFormat,
  getCellByAliases,
  isRecognizedCsvHeader,
  mapCsvHeadersToFields,
  resolveCsvHeaderField,
} from "@/lib/csvTradeParsers"

export type CsvImportDiagnostics = {
  format: CsvFileFormat
  formatLabel: string
  detectedColumns: string[]
  supportedColumnCount: number
  missingRequired: string[]
  unknownColumns: string[]
  unknownColumnCount: number
  rowFailureSamples: { rowNumber: number; reason: string }[]
  explanation: string
}

const FORMAT_LABELS: Record<CsvFileFormat, string> = {
  tradovate: "Tradovate",
  tradezella: "TradeZella",
  entered_exited: "Entry / exit timestamps",
  flexible: "Flexible (header aliases)",
}

type RequiredCheck = {
  label: string
  satisfied: (row: CsvRow) => boolean
}

function cellPresent(row: CsvRow, aliases: readonly string[]): boolean {
  return getCellByAliases(row, aliases) != null
}

function requiredChecksForFormat(format: CsvFileFormat): RequiredCheck[] {
  switch (format) {
    case "tradovate":
      return [
        {
          label: "Buy / entry price",
          satisfied: (row) =>
            cellPresent(row, ["buyPrice", "buy price", "entry price", "entry"]),
        },
        {
          label: "Sell / exit price",
          satisfied: (row) =>
            cellPresent(row, ["sellPrice", "sell price", "exit price", "exit"]),
        },
        { label: "PnL", satisfied: (row) => cellPresent(row, ["pnl", "p&l", "p/l", "net pnl"]) },
      ]
    case "tradezella":
      return [
        { label: "PnL", satisfied: (row) => cellPresent(row, ["p&l", "net p&l", "gross p&l"]) },
        {
          label: "Date",
          satisfied: (row) =>
            cellPresent(row, [
              "open date",
              "close date",
              "date",
              "trade date",
              "entry date",
              "exit date",
            ]),
        },
      ]
    case "entered_exited":
      return [
        {
          label: "Entry time",
          satisfied: (row) =>
            cellPresent(row, [
              "EnteredAt",
              "entered at",
              "entered_at",
              "entry time",
              "EntryTime",
              "open time",
              "OpenDateTime",
              "start time",
            ]),
        },
        {
          label: "Exit time",
          satisfied: (row) =>
            cellPresent(row, [
              "ExitedAt",
              "exited at",
              "exited_at",
              "exit time",
              "ExitTime",
              "close time",
              "CloseDateTime",
              "end time",
            ]),
        },
      ]
    case "flexible":
      return [
        {
          label: "Date",
          satisfied: (row) => Boolean(mapCsvHeadersToFields(row).date?.trim()),
        },
        {
          label: "Symbol",
          satisfied: (row) => Boolean(mapCsvHeadersToFields(row).symbol?.trim()),
        },
        {
          label: "Direction",
          satisfied: (row) => Boolean(mapCsvHeadersToFields(row).direction?.trim()),
        },
        {
          label: "PnL",
          satisfied: (row) => Boolean(mapCsvHeadersToFields(row).pnl?.trim()),
        },
      ]
  }
}

const LOGICAL_FIELD_LABELS: Record<LogicalField, string> = {
  date: "Date",
  symbol: "Symbol",
  direction: "Direction",
  entry_price: "Entry price",
  exit_price: "Exit price",
  pnl: "PnL",
  contracts: "Size / qty",
  points: "Points",
  rr: "R:R",
  session: "Session",
  account_type: "Account type",
  mode: "Mode",
  account_name: "Account",
  account_id: "Account ID",
  account_size: "Account size",
  strategy: "Strategy",
  commission: "Commission",
  fees: "Fees",
  swap: "Swap",
  notes: "Notes",
  entryTime: "Entry time",
  exitTime: "Exit time",
  duration: "Duration",
}

const OPTIONAL_FLEX_FIELDS: LogicalField[] = [
  "entry_price",
  "exit_price",
  "contracts",
  "entryTime",
  "exitTime",
  "session",
  "account_name",
  "commission",
  "fees",
]

function collectDetectedColumns(row: CsvRow, format: CsvFileFormat): string[] {
  const labels = new Set<string>()

  for (const key of Object.keys(row)) {
    if (!isRecognizedCsvHeader(key, format)) continue
    const val = String(row[key] ?? "").trim()
    if (!val) continue

    const logical = resolveCsvHeaderField(key)
    if (logical) {
      labels.add(LOGICAL_FIELD_LABELS[logical])
      continue
    }

    if (format === "tradovate") {
      const nk = key.toLowerCase()
      if (nk.includes("symbol") || nk.includes("contract")) labels.add("Symbol")
      else if (nk.includes("pnl") || nk.includes("p&l")) labels.add("PnL")
      else if (nk.includes("buy") || nk.includes("entry")) labels.add("Entry price")
      else if (nk.includes("sell") || nk.includes("exit")) labels.add("Exit price")
      else if (nk.includes("time") || nk.includes("timestamp")) labels.add("Time")
      else if (nk.includes("qty") || nk.includes("size")) labels.add("Size / qty")
      else labels.add(key.trim())
    } else {
      labels.add(key.trim())
    }
  }

  if (format === "flexible") {
    const mapped = mapCsvHeadersToFields(row)
    for (const field of OPTIONAL_FLEX_FIELDS) {
      if (mapped[field]?.trim()) labels.add(LOGICAL_FIELD_LABELS[field])
    }
  }

  return [...labels].sort((a, b) => a.localeCompare(b))
}

function collectUnknownColumns(row: CsvRow, format: CsvFileFormat): string[] {
  return Object.keys(row)
    .map((k) => k.trim())
    .filter((k) => k.length > 0 && !isRecognizedCsvHeader(k, format))
    .sort((a, b) => a.localeCompare(b))
}

function buildExplanation(
  parseResult: BuildTradesFromParsedCsvResult,
  missingRequired: string[],
  unknownColumns: string[],
  formatLabel: string
): string {
  const { summary } = parseResult
  if (summary.total === 0) {
    return "The file appears empty or has no data rows after skipping blank lines."
  }
  if (summary.success === summary.total) {
    return ""
  }
  if (summary.success === 0) {
    if (missingRequired.length > 0) {
      return `We detected a ${formatLabel} style CSV, but required columns are missing or empty in your first data row: ${missingRequired.join(", ")}.`
    }
    if (unknownColumns.length > 0) {
      return `We could not match several column headers to TradeTraxs fields. Add standard names (Date, Symbol, Direction, PnL) or submit a sample via CSV support.`
    }
    return `No rows could be imported using the ${formatLabel} parser. See row-level errors below.`
  }
  return `${summary.failed} of ${summary.total} row(s) could not be imported. Successful rows can still be imported.`
}

/** Read-only diagnostics for failed or partial CSV imports (does not change parsing). */
export function buildCsvImportDiagnostics(
  rows: CsvRow[],
  parseResult: BuildTradesFromParsedCsvResult
): CsvImportDiagnostics | null {
  if (!rows.length) return null

  const firstRow = rows[0]
  const format = detectCsvFileFormat(firstRow)
  const formatLabel = FORMAT_LABELS[format]

  const required = requiredChecksForFormat(format)
  const missingRequired = required
    .filter((check) => !check.satisfied(firstRow))
    .map((check) => check.label)

  const detectedColumns = collectDetectedColumns(firstRow, format)
  const unknownColumns = collectUnknownColumns(firstRow, format)

  const rowFailureSamples = parseResult.rowResults
    .filter((r): r is { ok: false; rowNumber: number; reason: string } => !r.ok)
    .slice(0, 5)
    .map((r) => ({ rowNumber: r.rowNumber, reason: r.reason }))

  const explanation = buildExplanation(
    parseResult,
    missingRequired,
    unknownColumns,
    formatLabel
  )

  const hasFailures = parseResult.summary.success < parseResult.summary.total
  const hasIssues =
    hasFailures || missingRequired.length > 0 || unknownColumns.length > 0

  if (!hasIssues && !explanation) return null

  return {
    format,
    formatLabel,
    detectedColumns,
    supportedColumnCount: detectedColumns.length,
    missingRequired,
    unknownColumns,
    unknownColumnCount: unknownColumns.length,
    rowFailureSamples,
    explanation,
  }
}
