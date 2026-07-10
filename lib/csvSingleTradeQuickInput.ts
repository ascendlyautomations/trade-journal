import type { CsvTradeInsert } from "@/lib/csvTradeParsers"
import {
  quickTradeFormPatchFromCsvTrade,
  type QuickTradeCsvFormPatch,
} from "@/lib/parseQuickCsvPaste"

/** True when exactly one valid trade was parsed from a CSV upload. */
export function shouldRouteCsvImportToQuickInput(
  parsedTrades: readonly unknown[]
): boolean {
  return parsedTrades.length === 1
}

export function buildQuickInputPatchFromCsvTrade(
  trade: CsvTradeInsert
): QuickTradeCsvFormPatch {
  return quickTradeFormPatchFromCsvTrade(trade)
}
