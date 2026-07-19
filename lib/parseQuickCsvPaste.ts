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

/** Max trades shown/processed per Quick Trade batch before auto-continuing. */
export const QUICK_CSV_BATCH_SIZE = 10

export const QUICK_CSV_PARSE_FAILED_MESSAGE = "Unable to read this CSV row."

export const QUICK_CSV_EMPTY_MESSAGE =
  "No trades found in this CSV. Check that your file has a header row and at least one trade."

export type QuickTradeCsvFormPatch = {
  ticker: string
  pnl: string
  points: string
  contracts: string
  rr: string
  direction: "Long" | "Short" | null
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
  | { ok: true; patches: QuickTradeCsvFormPatch[]; patch: QuickTradeCsvFormPatch }
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

/**
 * Extract all trade rows from Quick CSV paste/upload text.
 * Supports header + N data rows, header + single value line, or headerless single line.
 */
function extractCsvRows(
  text: string
):
  | { ok: true; rows: CsvRow[] }
  | { ok: false; code: "empty" | "parse_failed" } {
  const trimmed = text.trim()
  if (!trimmed) return { ok: false, code: "empty" }

  const rawLines = nonEmptyRawLines(trimmed)

  const headerParse = Papa.parse<CsvRow>(trimmed, {
    header: true,
    skipEmptyLines: true,
    transformHeader: (h: string) => stripBom(String(h).trim()),
  })

  const dataRows = normalizeParsedCsvRows(
    (headerParse.data ?? []).filter(Boolean) as CsvRow[]
  )

  if (dataRows.length >= 1) {
    return { ok: true, rows: dataRows }
  }

  if (rawLines.length === 2) {
    const headerLine = rawLines[0].map((cell) => String(cell ?? "").trim())
    const valueLine = rawLines[1].map((cell) => String(cell ?? "").trim())
    return { ok: true, rows: [rowFromHeaderLinePair(headerLine, valueLine)] }
  }

  if (rawLines.length === 1) {
    const cells = rawLines[0].map((cell) => String(cell ?? "").trim())
    const row = headerlessRowFromCells(cells)
    if (!row) return { ok: false, code: "parse_failed" }
    return { ok: true, rows: [row] }
  }

  if (rawLines.length === 0) return { ok: false, code: "empty" }
  return { ok: false, code: "parse_failed" }
}

export function quickTradeFormPatchFromCsvTrade(
  trade: CsvTradeInsert
): QuickTradeCsvFormPatch {
  const entryDate =
    toDateInputValue(trade.entry_time) || toDateInputValue(trade.date) || ""
  const exitDate =
    toDateInputValue(trade.exit_time) || toDateInputValue(trade.date) || entryDate

  const direction =
    trade.direction === "Long" || trade.direction === "Short"
      ? trade.direction
      : null

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
    direction,
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

function messageForExtractError(code: "empty" | "parse_failed"): string {
  if (code === "empty") return QUICK_CSV_EMPTY_MESSAGE
  return QUICK_CSV_PARSE_FAILED_MESSAGE
}

/** Parse CSV trade(s) through the standard import pipeline (1–N rows). */
export function parseQuickCsvImport(text: string): ParseQuickCsvImportResult {
  const extracted = extractCsvRows(text)
  if (!extracted.ok) {
    return { ok: false, message: messageForExtractError(extracted.code) }
  }

  const parsed = buildTradesFromParsedCsv(
    extracted.rows,
    QUICK_CSV_PLACEHOLDER_USER_ID
  )

  if (parsed.parsedTrades.length === 0) {
    return { ok: false, message: QUICK_CSV_PARSE_FAILED_MESSAGE }
  }

  const patches = parsed.parsedTrades.map(quickTradeFormPatchFromCsvTrade)
  return {
    ok: true,
    patches,
    patch: patches[0],
  }
}

/** Read a `.csv` file and autofill trade(s) through the standard import pipeline. */
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
