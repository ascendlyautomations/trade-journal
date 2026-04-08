export type CsvRow = Record<string, string>

export type CsvTradeInsert = {
  user_id: string
  ticker: string
  entry_price: number
  exit_price: number
  entry_time: string
  exit_time: string
  direction: string
  pnl: number
  contracts: number
  rr: number
  points: number
  date: string
  created_at: string
  session: string
  account_type: string
  notes: string
  public_description: string
  image_url: null
  account_size: string
  account_id: string
  reviewed: boolean
}

export function isTradovateCsvRow(row: CsvRow): boolean {
  return Object.keys(row).includes("buyPrice")
}

export function parseTradovateRow(row: CsvRow, userId: string): CsvTradeInsert {
  const entry = Number(row["buyPrice"])
  const exit = Number(row["sellPrice"])

  const pnlRaw = row["pnl"] || "0"
  const pnl = Number(
    String(pnlRaw)
      .replace("$", "")
      .replace(/,/g, "")
      .replace("(", "-")
      .replace(")", "")
      .trim() || "0"
  )

  const direction = exit > entry ? "Long" : "Short"

  const entryTime = new Date(row["boughtTimestamp"])
  const exitTime = new Date(row["soldTimestamp"])
  const entryOk = !Number.isNaN(entryTime.getTime())
  const exitOk = !Number.isNaN(exitTime.getTime())
  const entryIso = entryOk ? entryTime.toISOString() : new Date().toISOString()
  const exitIso = exitOk ? exitTime.toISOString() : entryIso

  return {
    user_id: userId,

    ticker: row["symbol"] ?? "",

    entry_price: entry,
    exit_price: exit,

    entry_time: entryIso,
    exit_time: exitIso,

    direction,

    pnl,
    contracts: Number(row["qty"]) || 1,

    rr: 0,
    points: Math.abs(exit - entry),

    date: entryIso,
    created_at: entryIso,

    session: "NY",
    account_type: "Imported",

    notes: "",
    public_description: "",
    image_url: null,

    account_size: "",
    account_id: "",
    reviewed: false,
  }
}

export function buildCleanCsvTrade(row: CsvRow, userId: string): CsvTradeInsert {
  const entry = Number(row["Entry Price"])
  const exit = Number(row["Exit Price"])
  const date = new Date(row["Date"])
  const dateIso = Number.isNaN(date.getTime())
    ? new Date().toISOString()
    : date.toISOString()

  return {
    user_id: userId,

    ticker: row["Symbol"] ?? "",

    entry_price: entry,
    exit_price: exit,

    entry_time: dateIso,
    exit_time: dateIso,

    direction: row["Direction"] ?? "",

    pnl: Number(row["PnL"]),
    contracts: Number(row["Contracts"]) || 1,

    rr: 0,
    points: 0,

    date: dateIso,
    created_at: dateIso,

    session: "NY",
    account_type: "Imported",

    notes: "",
    public_description: "",
    image_url: null,

    account_size: "",
    account_id: "",
    reviewed: false,
  }
}

export function buildTradesFromParsedCsv(
  parsed: CsvRow[],
  userId: string
): { isTradovate: boolean; parsedTrades: CsvTradeInsert[] } {
  if (parsed.length === 0) {
    return { isTradovate: false, parsedTrades: [] }
  }
  const isTradovate = isTradovateCsvRow(parsed[0])
  const parsedTrades = isTradovate
    ? parsed.map((row) => parseTradovateRow(row, userId))
    : parsed.map((row) => buildCleanCsvTrade(row, userId))
  return { isTradovate, parsedTrades }
}
