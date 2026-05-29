import {
  type CsvRow,
  isTradovateCsvRow,
  isTradeZellaShapedRow,
} from "@/lib/csvTradeParsers"

export const CSV_SUPPORT_BROKERS = [
  "Tradovate",
  "NinjaTrader",
  "TradeZella",
  "TopStep",
  "Quantower",
  "Other",
] as const

export type CsvSupportBroker = (typeof CSV_SUPPORT_BROKERS)[number]

/** Best-effort broker label from CSV headers/shape (no parser changes). */
export function detectCsvBrokerHint(rows: CsvRow[]): CsvSupportBroker | null {
  if (!rows.length) return null
  const first = rows[0]
  if (isTradovateCsvRow(first)) return "Tradovate"
  if (isTradeZellaShapedRow(first)) return "TradeZella"

  const headerBlob = Object.keys(first).join(" ").toLowerCase()
  if (/ninja|nt8/.test(headerBlob)) return "NinjaTrader"
  if (/top\s*step|topstep/.test(headerBlob)) return "TopStep"
  if (/quantower/.test(headerBlob)) return "Quantower"
  if (/tradovate/.test(headerBlob)) return "Tradovate"
  if (/tradezella|zella/.test(headerBlob)) return "TradeZella"

  return null
}

export function isCsvFormatUnrecognized(summary: {
  total: number
  success: number
}): boolean {
  return summary.total > 0 && summary.success === 0
}

export function csvSupportUrl(brokerHint?: string | null): string {
  if (!brokerHint) return "/csv-support"
  const q = new URLSearchParams({ broker: brokerHint })
  return `/csv-support?${q.toString()}`
}
