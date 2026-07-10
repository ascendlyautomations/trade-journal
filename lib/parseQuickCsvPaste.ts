import Papa from "papaparse"
import {
  buildTradesFromParsedCsv,
  normalizeParsedCsvRows,
  parseFlexibleTradeDate,
  stripBom,
  type CsvRow,
  type CsvTradeInsert,
} from "@/lib/csvTradeParsers"
import { toDateInputValue, toTimeInputValue } from "@/lib/inputTradeDateTime"

const QUICK_CSV_PLACEHOLDER_USER_ID = "00000000-0000-0000-0000-000000000000"

export const QUICK_CSV_MULTI_TRADE_MESSAGE =
  "This Quick Trade importer only supports one trade at a time. Please upload a CSV containing a header row and a single trade."

export const QUICK_CSV_PARSE_FAILED_MESSAGE = "Unable to read this CSV row."

export type QuickTradeCsvFormPatch = {
  ticker: string
  pnl: string
  points: string
  contracts: string
  rr: string
  entryDate: string
  exitDate: string
  entryTime: string
  exitTime: string
  entryPrice: string
  exitPrice: string
  description: string
  accountId: string | null
  accountName: string | null
}

export type ParseQuickCsvImportResult =
  | { ok: true; patch: QuickTradeCsvFormPatch }
  | { ok: false; message: string }

function splitDateTimeCell(raw: string): { date: string; time: string } {
  const trimmed = raw.trim()
  if (!trimmed) return { date: "", time: "" }

  const iso = parseFlexibleTradeDate(trimmed)
  if (iso) {
    return {
      date: toDateInputValue(iso),
      time: toTimeInputValue(iso),
    }
  }

  const [datePart, timePart] = trimmed.split(/\s+/, 2)
  return {
    date: datePart ?? "",
    time: timePart ? timePart.slice(0, 5) : "",
  }
}

/** Map headerless single-line paste cells to alias keys the flexible CSV path recognizes. */
function headerlessRowFromCells(cells: string[]): CsvRow | null {
  const trimmed = cells.map((c) => String(c ?? "").trim())
  if (trimmed.length < 5) return null

  const [
    symbol,
    entered,
    exited,
    size,
    points,
    pnl,
    entryPrice,
    exitPrice,
  ] = trimmed

  if (!symbol || !entered || !exited || !pnl) return null

  const entry = splitDateTimeCell(entered)
  const exit = splitDateTimeCell(exited)
  const tradeDate = entry.date || exit.date
  if (!tradeDate) return null

  const row: CsvRow = {
    symbol,
    date: tradeDate,
    direction: "Long",
    pnl,
    contracts: size,
    points,
    "entry time": entry.time || entered,
    "exit time": exit.time || exited,
  }

  if (entryPrice) row["entry price"] = entryPrice
  if (exitPrice) row["exit price"] = exitPrice

  return row
}

function rowFromHeaderLinePair(headerLine: string[], valueLine: string[]): CsvRow {
  const row: CsvRow = {}
  headerLine.forEach((header, index) => {
    const key = stripBom(String(header ?? "").trim())
    if (!key) return
    row[key] = String(valueLine[index] ?? "").trim()
  })
  return row
}

function nonEmptyRawLines(text: string): string[][] {
  const rawParse = Papa.parse<string[]>(text.trim(), {
    header: false,
    skipEmptyLines: true,
  })

  return (rawParse.data ?? []).filter(
    (line) => Array.isArray(line) && line.some((cell) => String(cell ?? "").trim())
  ) as string[][]
}

function extractSingleCsvRow(
  text: string
):
  | { ok: true; row: CsvRow }
  | { ok: false; code: "empty" | "multi_trade" | "parse_failed" } {
  const trimmed = text.trim()
  if (!trimmed) return { ok: false, code: "empty" }

  const rawLines = nonEmptyRawLines(trimmed)
  if (rawLines.length > 2) {
    return { ok: false, code: "multi_trade" }
  }

  const headerParse = Papa.parse<CsvRow>(trimmed, {
    header: true,
    skipEmptyLines: true,
    transformHeader: (h: string) => stripBom(String(h).trim()),
  })

  const dataRows = normalizeParsedCsvRows(
    (headerParse.data ?? []).filter(Boolean) as CsvRow[]
  )

  if (dataRows.length > 1) {
    return { ok: false, code: "multi_trade" }
  }

  if (dataRows.length === 1) {
    return { ok: true, row: dataRows[0] }
  }

  if (rawLines.length === 2) {
    const headerLine = rawLines[0].map((cell) => String(cell ?? "").trim())
    const valueLine = rawLines[1].map((cell) => String(cell ?? "").trim())
    return { ok: true, row: rowFromHeaderLinePair(headerLine, valueLine) }
  }

  if (rawLines.length === 1) {
    const cells = rawLines[0].map((cell) => String(cell ?? "").trim())
    const row = headerlessRowFromCells(cells)
    if (!row) return { ok: false, code: "parse_failed" }
    return { ok: true, row }
  }

  return { ok: false, code: "empty" }
}

export function quickTradeFormPatchFromCsvTrade(
  trade: CsvTradeInsert
): QuickTradeCsvFormPatch {
  const entryDate =
    toDateInputValue(trade.entry_time) || toDateInputValue(trade.date) || ""
  const exitDate =
    toDateInputValue(trade.exit_time) || toDateInputValue(trade.date) || entryDate

  return {
    ticker: trade.ticker ?? "",
    pnl: Number.isFinite(trade.pnl) ? String(trade.pnl) : "",
    points:
      trade.points != null && Number.isFinite(trade.points)
        ? String(trade.points)
        : "",
    contracts:
      trade.contracts != null && Number.isFinite(trade.contracts)
        ? String(trade.contracts)
        : "",
    rr:
      trade.rr != null && Number.isFinite(trade.rr) ? String(trade.rr) : "",
    entryDate,
    exitDate,
    entryTime: toTimeInputValue(trade.entry_time),
    exitTime: toTimeInputValue(trade.exit_time),
    entryPrice:
      trade.entry_price != null && Number.isFinite(trade.entry_price)
        ? String(trade.entry_price)
        : "",
    exitPrice:
      trade.exit_price != null && Number.isFinite(trade.exit_price)
        ? String(trade.exit_price)
        : "",
    description: String(trade.notes || trade.public_description || "").trim(),
    accountId: trade.account_id != null ? String(trade.account_id) : null,
    accountName: trade.account_name != null ? String(trade.account_name) : null,
  }
}

function messageForExtractError(
  code: "empty" | "multi_trade" | "parse_failed"
): string {
  if (code === "multi_trade") return QUICK_CSV_MULTI_TRADE_MESSAGE
  return QUICK_CSV_PARSE_FAILED_MESSAGE
}

/** Parse one CSV trade (header + single row) through the standard import pipeline. */
export function parseQuickCsvImport(text: string): ParseQuickCsvImportResult {
  const extracted = extractSingleCsvRow(text)
  if (!extracted.ok) {
    return { ok: false, message: messageForExtractError(extracted.code) }
  }

  const parsed = buildTradesFromParsedCsv(
    [extracted.row],
    QUICK_CSV_PLACEHOLDER_USER_ID
  )

  if (parsed.parsedTrades.length > 1) {
    return { ok: false, message: QUICK_CSV_MULTI_TRADE_MESSAGE }
  }

  const trade = parsed.parsedTrades[0]
  if (!trade) {
    return { ok: false, message: QUICK_CSV_PARSE_FAILED_MESSAGE }
  }

  return {
    ok: true,
    patch: quickTradeFormPatchFromCsvTrade(trade),
  }
}

/** Read a `.csv` file and autofill one trade through the standard import pipeline. */
export async function parseQuickCsvFile(
  file: File
): Promise<ParseQuickCsvImportResult> {
  const name = file.name.trim().toLowerCase()
  if (!name.endsWith(".csv")) {
    return { ok: false, message: "Please upload a CSV file." }
  }

  let text: string
  try {
    text = await file.text()
  } catch {
    return { ok: false, message: QUICK_CSV_PARSE_FAILED_MESSAGE }
  }

  return parseQuickCsvImport(text)
}

/** @deprecated Use parseQuickCsvImport */
export function parseQuickCsvPaste(text: string): ParseQuickCsvImportResult {
  return parseQuickCsvImport(text)
}
