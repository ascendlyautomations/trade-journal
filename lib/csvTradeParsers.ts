import { parseCsvNumeric } from "./parseCsvNumeric"
import { normalizeFuturesSymbol } from "./normalizeFuturesSymbol"

export type CsvRow = Record<string, string>

/** Insert shape aligned with dashboard CSV import + trades table. */
export type CsvTradeInsert = {
  user_id: string
  ticker: string
  entry_price: number | null
  exit_price: number | null
  entry_time: string | null
  exit_time: string | null
  direction: string
  pnl: number
  contracts: number
  rr: number | null
  points: number | null
  date: string
  created_at: string
  session: string | null
  account_type: string
  mode: string | null
  notes: string
  public_description: string
  image_url: null
  account_size: string | null
  account_id: string | null
  account_name: string | null
  strategy?: string | null
  reviewed: boolean
  duration_seconds: number | null
  duration_text: string | null
  /** CSV imports are always private; user can publish from the trade editor. */
  is_public: false
}

export type LogicalField =
  | "date"
  | "symbol"
  | "direction"
  | "entry_price"
  | "exit_price"
  | "pnl"
  | "contracts"
  | "points"
  | "rr"
  | "session"
  | "account_type"
  | "mode"
  | "account_name"
  | "account_id"
  | "account_size"
  | "strategy"
  | "commission"
  | "fees"
  | "swap"
  | "notes"
  | "entryTime"
  | "exitTime"
  | "duration"

/** Normalized header → logical field (first alias wins at build time). */
const HEADER_ALIAS_TO_FIELD = buildHeaderAliasMap()

function buildHeaderAliasMap(): Map<string, LogicalField> {
  const groups: Record<LogicalField, readonly string[]> = {
    date: [
      "date",
      "trade date",
      "entry date",
      "close date",
      "closed date",
      "open date",
      "exec date",
      "execution date",
    ],
    symbol: [
      "symbol",
      "ticker",
      "instrument",
      "contract",
      "underlying",
      "product",
    ],
    direction: [
      "direction",
      "side",
      "buy sell",
      "position",
      "action",
      "type",
      "long short",
      "order side",
    ],
    entry_price: [
      "entry price",
      "entry",
      "avg entry",
      "open price",
      "entry px",
      "avg entry price",
      "buy price",
    ],
    exit_price: [
      "exit price",
      "exit",
      "avg exit",
      "close price",
      "avg exit price",
      "sell price",
    ],
    pnl: [
      "pnl",
      "p l",
      "profit",
      "net pnl",
      "realized pnl",
      "realized p l",
      "gain",
      "net profit",
      "net",
      "pl",
    ],
    contracts: [
      "contracts",
      "qty",
      "quantity",
      "size",
      "volume",
      "lots",
      "shares",
      "position size",
    ],
    points: ["points", "net points", "tick gain", "ticks"],
    rr: ["rr", "r r", "risk reward", "risk reward ratio", "reward risk"],
    session: ["session", "trading session", "market session"],
    account_type: ["account type", "acct type"],
    mode: ["mode", "account mode", "trading mode"],
    account_name: [
      "account",
      "account name",
      "firm",
      "broker",
      "prop firm",
      "workspace",
    ],
    strategy: ["strategy", "setup", "playbook", "system"],
    account_id: ["account id", "acct id", "account number", "acct", "account #"],
    account_size: ["account size", "eval size", "funded size", "acct size"],
    commission: ["commission", "commissions", "comm", "broker commission"],
    fees: ["fees", "fee", "exchange fee", "platform fee"],
    swap: ["swap", "swap fee", "overnight fee", "financing"],
    notes: ["notes", "comment", "description", "remarks"],
    entryTime: [
      "entry time",
      "entrytime",
      "open time",
      "time in",
      "entry timestamp",
      "in time",
    ],
    exitTime: [
      "exit time",
      "exittime",
      "close time",
      "time out",
      "exit timestamp",
      "out time",
    ],
    duration: ["duration", "trade duration", "hold time", "time in trade", "hold"],
  }

  const map = new Map<string, LogicalField>()
  for (const [field, aliases] of Object.entries(groups) as [
    LogicalField,
    readonly string[],
  ][]) {
    for (const a of aliases) {
      const k = normalizeHeaderKey(a)
      if (!map.has(k)) map.set(k, field)
    }
  }
  return map
}

export function stripBom(s: string): string {
  if (!s) return s
  const t = s.trimStart()
  if (t.charCodeAt(0) === 0xfeff) return t.slice(1)
  return s.replace(/^\uFEFF/, "")
}

export function normalizeHeaderKey(header: string): string {
  let s = stripBom(header).trim().toLowerCase()
  s = s.replace(/[\u200B-\u200D\uFEFF]/g, "")
  s = s.replace(/[_\-]+/g, " ")
  s = s.replace(/[^a-z0-9\s]/gi, " ")
  s = s.replace(/\s+/g, " ").trim()
  return s
}

/** Normalize raw Papa rows: trim keys (BOM), trim string cell values. */
export function normalizeParsedCsvRows(rows: CsvRow[]): CsvRow[] {
  return rows
    .filter((r) => r && typeof r === "object" && Object.keys(r).length > 0)
    .map((row) => {
      const next: CsvRow = {}
      for (const [k, v] of Object.entries(row)) {
        const key = stripBom(String(k).trim())
        if (!key) continue
        next[key] = v == null ? "" : String(v).trim()
      }
      return next
    })
}

export function mapCsvHeadersToFields(row: CsvRow): Partial<Record<LogicalField, string>> {
  const out: Partial<Record<LogicalField, string>> = {}
  for (const [rawKey, val] of Object.entries(row)) {
    const nk = normalizeHeaderKey(rawKey)
    const field = HEADER_ALIAS_TO_FIELD.get(nk)
    if (!field) continue
    const s = val == null ? "" : String(val).trim()
    if (s !== "") out[field] = s
  }
  return out
}

/** @deprecated use parseCsvNumeric from ./parseCsvNumeric — kept for call-site clarity */
export const parseMoneyLike = parseCsvNumeric

/** Parse duration cell → whole seconds (plain integer, H:M:S, Xm Ys, etc.). */
export function parseDurationCsvValue(raw: string): number | null {
  const s = raw.trim().toLowerCase()
  if (!s) return null
  if (/^\d+$/.test(s)) {
    const v = parseInt(s, 10)
    return Number.isFinite(v) && v >= 0 ? v : null
  }
  const compact = s.replace(/\s/g, "")
  const hms = /^(\d+):(\d{2}):(\d{2})$/.exec(compact)
  if (hms) {
    return (
      parseInt(hms[1], 10) * 3600 + parseInt(hms[2], 10) * 60 + parseInt(hms[3], 10)
    )
  }
  const ms = /^(\d+):(\d{2})$/.exec(compact)
  if (ms) {
    return parseInt(ms[1], 10) * 60 + parseInt(ms[2], 10)
  }
  let total = 0
  let any = false
  const h = /(\d+(?:\.\d+)?)\s*h/.exec(s)
  const m = /(\d+(?:\.\d+)?)\s*(?:m(?![a-z])|min(?:ute)?s?)/i.exec(s)
  const sec = /(\d+(?:\.\d+)?)\s*(?:s(?![a-z])|sec(?:ond)?s?)/i.exec(s)
  if (h) {
    total += parseFloat(h[1]) * 3600
    any = true
  }
  if (m) {
    total += parseFloat(m[1]) * 60
    any = true
  }
  if (sec) {
    total += parseFloat(sec[1])
    any = true
  }
  if (!any) return null
  return Math.max(0, Math.round(total))
}

/** Merge trade date (ISO) with optional time-only or full datetime cell. */
export function combineTradeDateAndTime(
  tradeDateIso: string,
  timeRaw: string
): string | null {
  const t = timeRaw.trim()
  if (!t) return tradeDateIso

  if (/^\d{4}-\d{2}-\d{2}/.test(t)) {
    const d = new Date(t.includes("T") ? t : `${t}T12:00:00`)
    return Number.isNaN(d.getTime()) ? null : d.toISOString()
  }

  const base = new Date(tradeDateIso)
  if (Number.isNaN(base.getTime())) return null
  const y = base.getFullYear()
  const mo = base.getMonth()
  const day = base.getDate()

  const clock = /^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)?$/i.exec(t)
  if (clock) {
    let hour = parseInt(clock[1], 10)
    const minute = parseInt(clock[2], 10)
    const second = clock[3] ? parseInt(clock[3], 10) : 0
    const ap = clock[4]?.toUpperCase()
    if (ap === "PM" && hour < 12) hour += 12
    if (ap === "AM" && hour === 12) hour = 0
    const d = new Date(y, mo, day, hour, minute, second)
    return Number.isNaN(d.getTime()) ? null : d.toISOString()
  }

  const d2 = new Date(`${y}-${String(mo + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}T${t}`)
  return Number.isNaN(d2.getTime()) ? tradeDateIso : d2.toISOString()
}

export function normalizeDirection(raw: string): "Long" | "Short" | null {
  const s = String(raw).trim().toLowerCase()
  if (!s) return null
  if (/^(long|buy|b|l|cover buy|buy to open|bot)$/i.test(s)) return "Long"
  if (/^(short|sell|s|ss|sell short|sold short|sl)$/i.test(s)) return "Short"
  if (s === "long" || s.includes("long")) return "Long"
  if (s === "short" || s.includes("short")) return "Short"
  return null
}

/** Parse common broker / Excel date strings → ISO timestamp. */
export function parseFlexibleTradeDate(raw: string): string | null {
  const s = String(raw).trim()
  if (!s) return null

  if (/^\d{4}-\d{2}-\d{2}/.test(s)) {
    const d = new Date(s.includes("T") ? s : `${s}T12:00:00`)
    if (!Number.isNaN(d.getTime())) return d.toISOString()
  }

  const us = /^(\d{1,2})\/(\d{1,2})\/(\d{2,4})(?:\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)?)?$/i.exec(
    s
  )
  if (us) {
    const month = parseInt(us[1], 10)
    const day = parseInt(us[2], 10)
    let year = parseInt(us[3], 10)
    if (year < 100) year += year >= 70 ? 1900 : 2000
    let h = 12,
      m = 0,
      sec = 0
    if (us[4] != null) {
      h = parseInt(us[4], 10) % 24
      m = parseInt(us[5], 10)
      sec = us[6] ? parseInt(us[6], 10) : 0
      const ap = us[7]?.toUpperCase()
      if (ap === "PM" && h < 12) h += 12
      if (ap === "AM" && h === 12) h = 0
    }
    const d = new Date(year, month - 1, day, h, m, sec)
    if (
      !Number.isNaN(d.getTime()) &&
      d.getFullYear() === year &&
      d.getMonth() === month - 1 &&
      d.getDate() === day
    ) {
      return d.toISOString()
    }
  }

  const d2 = new Date(s)
  if (!Number.isNaN(d2.getTime())) return d2.toISOString()
  return null
}

export type CsvParseRowResult =
  | { ok: true; rowNumber: number; trade: CsvTradeInsert }
  | { ok: false; rowNumber: number; reason: string }

export type BuildTradesFromParsedCsvResult = {
  isTradovate: boolean
  parsedTrades: CsvTradeInsert[]
  rowResults: CsvParseRowResult[]
  summary: { total: number; success: number; failed: number }
}

export function isTradovateCsvRow(row: CsvRow): boolean {
  for (const k of Object.keys(row)) {
    const nk = normalizeHeaderKey(k)
    if (
      nk === "buyprice" ||
      nk === "sellprice" ||
      nk === "boughttimestamp" ||
      nk === "soldtimestamp"
    ) {
      return true
    }
  }
  return false
}

function getCellByAliases(row: CsvRow, aliases: readonly string[]): string | null {
  const normalizedToRaw = new Map<string, string>()
  for (const key of Object.keys(row)) normalizedToRaw.set(normalizeHeaderKey(key), key)
  for (const alias of aliases) {
    const rawKey = normalizedToRaw.get(normalizeHeaderKey(alias))
    if (!rawKey) continue
    const value = row[rawKey]
    if (value == null) continue
    const text = String(value).trim()
    if (text !== "") return text
  }
  return null
}

function logCsvRowDebug(label: string, payload: Record<string, unknown>) {
  if (process.env.NODE_ENV === "production") return
  console.debug(`[csv-import][${label}]`, payload)
}

export function parseTradovateRow(row: CsvRow, userId: string): CsvTradeInsert {
  const entryRaw = getCellByAliases(row, ["buyPrice", "buy price", "entry price", "entry"])
  const exitRaw = getCellByAliases(row, ["sellPrice", "sell price", "exit price", "exit"])
  const qtyRaw = getCellByAliases(row, ["qty", "quantity", "contracts", "size"])
  const symbolRaw = getCellByAliases(row, ["symbol", "ticker", "contract"])
  const normalizedTicker = normalizeFuturesSymbol(symbolRaw)
  const pnlRaw = getCellByAliases(row, ["pnl", "p&l", "p/l", "realized pnl", "net pnl"])
  const boughtTsRaw = getCellByAliases(row, ["boughtTimestamp", "bought timestamp", "entry time"])
  const soldTsRaw = getCellByAliases(row, ["soldTimestamp", "sold timestamp", "exit time"])
  const sideRaw = getCellByAliases(row, ["side", "direction", "action"])
  const durationRaw = getCellByAliases(row, [
    "duration",
    "trade duration",
    "hold time",
    "time in trade",
    "hold",
  ])

  const entry = entryRaw == null ? null : parseCsvNumeric(entryRaw)
  const exit = exitRaw == null ? null : parseCsvNumeric(exitRaw)
  if (entryRaw != null && entry === null) throw new Error(`Invalid buyPrice: "${entryRaw}"`)
  if (exitRaw != null && exit === null) throw new Error(`Invalid sellPrice: "${exitRaw}"`)

  if (pnlRaw == null) throw new Error("Missing PnL column/value")
  const pnl = parseCsvNumeric(pnlRaw)
  if (pnl === null) throw new Error(`Invalid PnL: "${pnlRaw}"`)

  const qtyParsed = qtyRaw == null ? null : parseCsvNumeric(qtyRaw)
  if (qtyRaw != null && (qtyParsed === null || !Number.isInteger(qtyParsed) || qtyParsed <= 0)) {
    throw new Error(`Invalid qty/contracts: "${qtyRaw}"`)
  }
  const contracts = qtyParsed != null ? qtyParsed : 1

  const directionFromSide = sideRaw ? normalizeDirection(sideRaw) : null
  const direction =
    directionFromSide ??
    (entry != null && exit != null ? (exit > entry ? "Long" : "Short") : "Long")

  const entryTime = new Date(boughtTsRaw ?? "")
  const exitTime = new Date(soldTsRaw ?? "")
  const entryOk = !Number.isNaN(entryTime.getTime())
  const exitOk = !Number.isNaN(exitTime.getTime())
  const nowIso = new Date().toISOString()
  const entryIso = entryOk ? entryTime.toISOString() : nowIso
  const exitIso = exitOk ? exitTime.toISOString() : entryIso

  const duration_text = durationRaw?.trim() || null
  let duration_seconds: number | null = null
  if (duration_text) {
    duration_seconds = parseDurationCsvValue(duration_text)
  } else if (entryOk && exitOk) {
    const delta = Math.round((exitTime.getTime() - entryTime.getTime()) / 1000)
    if (Number.isFinite(delta) && delta > 0) duration_seconds = delta
  }

  logCsvRowDebug("tradovate-row", {
    rawPnl: pnlRaw,
    parsedPnl: pnl,
    rawSymbol: symbolRaw ?? null,
    normalizedTicker,
    rawEntryTime: boughtTsRaw,
    rawExitTime: soldTsRaw,
    rawDurationText: duration_text,
    computedDurationSeconds: duration_seconds,
  })

  return {
    user_id: userId,
    ticker: normalizedTicker || (symbolRaw ?? ""),
    entry_price: entry,
    exit_price: exit,
    entry_time: entryIso,
    exit_time: exitIso,
    direction,
    pnl,
    contracts,
    rr: 0,
    points: entry != null && exit != null ? Math.abs(exit - entry) : null,
    date: entryIso,
    created_at: entryIso,
    session: "NY",
    account_type: "imported",
    mode: "live",
    notes: "",
    public_description: "",
    image_url: null,
    account_size: null,
    account_id: null,
    account_name: null,
    reviewed: false,
    duration_seconds,
    duration_text,
    is_public: false,
  }
}

function parseTradovateRowSafe(
  row: CsvRow,
  userId: string,
  rowNumber: number
): CsvParseRowResult {
  try {
    const hasBuy = getCellByAliases(row, ["buyPrice", "buy price", "entry price", "entry"])
    const hasSell = getCellByAliases(row, ["sellPrice", "sell price", "exit price", "exit"])
    if (hasBuy == null || hasSell == null) {
      return { ok: false, rowNumber, reason: "Tradovate row missing buy/sell price" }
    }
    const trade = parseTradovateRow(row, userId)
    return { ok: true, rowNumber, trade }
  } catch (e) {
    return {
      ok: false,
      rowNumber,
      reason: e instanceof Error ? e.message : "Tradovate parse error",
    }
  }
}

function buildFlexibleTradeInsert(
  f: Partial<Record<LogicalField, string>>,
  userId: string,
  rowNumber: number
): CsvParseRowResult {
  const dateRaw = f.date?.trim() ?? ""
  const symbolRaw = f.symbol?.trim() ?? ""
  const normalizedTicker = normalizeFuturesSymbol(symbolRaw)
  const dirRaw = f.direction?.trim() ?? ""
  const pnlRaw = f.pnl?.trim() ?? ""

  if (!dateRaw) return { ok: false, rowNumber, reason: "Missing required field: date" }
  if (!symbolRaw) return { ok: false, rowNumber, reason: "Missing required field: symbol" }
  if (!dirRaw) return { ok: false, rowNumber, reason: "Missing required field: direction" }
  if (pnlRaw === "") return { ok: false, rowNumber, reason: "Missing required field: PnL" }

  const dateIso = parseFlexibleTradeDate(dateRaw)
  if (!dateIso) {
    return { ok: false, rowNumber, reason: `Unrecognized date format: "${dateRaw}"` }
  }

  const direction = normalizeDirection(dirRaw)
  if (!direction) {
    return { ok: false, rowNumber, reason: `Invalid direction: "${dirRaw}"` }
  }

  const pnl = parseCsvNumeric(pnlRaw)
  if (pnl === null) {
    return { ok: false, rowNumber, reason: `Invalid PnL: "${pnlRaw}"` }
  }

  const entryN =
    f.entry_price != null && f.entry_price !== ""
      ? parseCsvNumeric(f.entry_price)
      : null
  const exitN =
    f.exit_price != null && f.exit_price !== ""
      ? parseCsvNumeric(f.exit_price)
      : null

  if (f.entry_price && f.entry_price !== "" && entryN === null) {
    return { ok: false, rowNumber, reason: `Invalid entry price: "${f.entry_price}"` }
  }
  if (f.exit_price && f.exit_price !== "" && exitN === null) {
    return { ok: false, rowNumber, reason: `Invalid exit price: "${f.exit_price}"` }
  }

  let contracts = 1
  if (f.contracts != null && f.contracts !== "") {
    const c = parseCsvNumeric(f.contracts)
    if (c === null || !Number.isInteger(c) || c < 0) {
      return { ok: false, rowNumber, reason: `Invalid contracts/qty: "${f.contracts}"` }
    }
    contracts = Math.max(0, c)
  }
  if (contracts === 0) contracts = 1

  let rr: number | null = null
  if (f.rr != null && f.rr !== "") {
    rr = parseCsvNumeric(f.rr)
    if (rr === null) {
      const cleaned = f.rr.replace(/[^0-9.\-]/g, "")
      const r = Number(cleaned)
      if (Number.isFinite(r)) rr = r
    }
  }

  let points: number | null = null
  if (f.points != null && f.points !== "") {
    const p = parseCsvNumeric(f.points)
    if (p !== null && Number.isFinite(p)) points = p
  }

  let entryTimeIso = dateIso
  let exitTimeIso = dateIso
  if (f.entryTime?.trim()) {
    const merged = combineTradeDateAndTime(dateIso, f.entryTime.trim())
    if (merged) entryTimeIso = merged
  }
  if (f.exitTime?.trim()) {
    const merged = combineTradeDateAndTime(dateIso, f.exitTime.trim())
    if (merged) exitTimeIso = merged
  }

  const duration_text = f.duration?.trim() || null
  let duration_seconds: number | null = null
  if (duration_text) {
    duration_seconds = parseDurationCsvValue(duration_text)
  } else {
    const a = new Date(entryTimeIso).getTime()
    const b = new Date(exitTimeIso).getTime()
    if (Number.isFinite(a) && Number.isFinite(b) && b > a) {
      duration_seconds = Math.round((b - a) / 1000)
    }
  }

  logCsvRowDebug("flex-row", {
    rowNumber,
    rawPnl: pnlRaw,
    parsedPnl: pnl,
    rawEntryTime: f.entryTime ?? null,
    rawExitTime: f.exitTime ?? null,
    rawDurationText: duration_text,
    rawCommission: f.commission ?? null,
    rawFees: f.fees ?? null,
    rawSwap: f.swap ?? null,
    computedDurationSeconds: duration_seconds,
  })

  const sessionVal = f.session?.trim() || null
  const acctTypeRaw = f.account_type?.trim() || ""
  const modeRaw = f.mode?.trim() || ""
  const account_type = acctTypeRaw ? acctTypeRaw.toLowerCase() : "imported"
  const mode = modeRaw
    ? modeRaw.toLowerCase()
    : account_type !== "imported"
      ? account_type
      : "live"

  const strategy = f.strategy?.trim() || null
  const commission =
    f.commission != null && f.commission !== "" ? parseCsvNumeric(f.commission) : null
  const fees = f.fees != null && f.fees !== "" ? parseCsvNumeric(f.fees) : null
  const swap = f.swap != null && f.swap !== "" ? parseCsvNumeric(f.swap) : null
  const importCostNotes: string[] = []
  if (commission !== null) importCostNotes.push(`Commission: ${commission}`)
  if (fees !== null) importCostNotes.push(`Fees: ${fees}`)
  if (swap !== null) importCostNotes.push(`Swap: ${swap}`)
  const baseNotes = f.notes?.trim() ?? ""
  const notes =
    importCostNotes.length > 0
      ? [baseNotes, importCostNotes.join(" | ")].filter(Boolean).join("\n")
      : baseNotes

  const trade: CsvTradeInsert = {
    user_id: userId,
    ticker: normalizedTicker,
    entry_price: entryN,
    exit_price: exitN,
    entry_time: entryTimeIso,
    exit_time: exitTimeIso,
    direction,
    pnl,
    contracts,
    rr,
    points,
    date: dateIso,
    created_at: dateIso,
    session: sessionVal && sessionVal.length > 0 ? sessionVal : null,
    account_type,
    mode,
    notes,
    public_description: "",
    image_url: null,
    account_size: f.account_size?.trim() || null,
    account_id: f.account_id?.trim() || null,
    account_name: f.account_name?.trim() || null,
    strategy,
    reviewed: false,
    duration_seconds,
    duration_text,
    is_public: false,
  }

  return { ok: true, rowNumber, trade }
}

/** Back-compat: flexible “clean” CSV (non-Tradovate). */
export function buildCleanCsvTrade(row: CsvRow, userId: string): CsvTradeInsert {
  const f = mapCsvHeadersToFields(row)
  const res = buildFlexibleTradeInsert(f, userId, 1)
  if (res.ok) return res.trade
  throw new Error(res.reason)
}

/** Force private flag on insert payloads (belt-and-suspenders). */
export function tradesInsertRowsPrivate<T extends Record<string, unknown>>(rows: T[]) {
  return rows.map((row) => ({ ...row, is_public: false }))
}

export function buildTradesFromParsedCsv(
  parsed: CsvRow[],
  userId: string
): BuildTradesFromParsedCsvResult {
  const rows = normalizeParsedCsvRows(parsed)
  const rowResults: CsvParseRowResult[] = []

  if (rows.length === 0) {
    return {
      isTradovate: false,
      parsedTrades: [],
      rowResults: [],
      summary: { total: 0, success: 0, failed: 0 },
    }
  }

  const isTradovate = isTradovateCsvRow(rows[0])

  if (isTradovate) {
    rows.forEach((row, i) => {
      const rowNumber = i + 2
      rowResults.push(parseTradovateRowSafe(row, userId, rowNumber))
    })
  } else {
    rows.forEach((row, i) => {
      const rowNumber = i + 2
      const f = mapCsvHeadersToFields(row)
      const keys = Object.keys(f)
      if (keys.length === 0) {
        rowResults.push({
          ok: false,
          rowNumber,
          reason: "No recognized columns — check headers match Date, Symbol, Direction, PnL, etc.",
        })
        return
      }
      rowResults.push(buildFlexibleTradeInsert(f, userId, rowNumber))
    })
  }

  const parsedTrades = rowResults
    .filter((r): r is Extract<CsvParseRowResult, { ok: true }> => r.ok)
    .map((r) => r.trade)

  const failed = rowResults.filter((r) => !r.ok).length
  return {
    isTradovate,
    parsedTrades,
    rowResults,
    summary: { total: rows.length, success: parsedTrades.length, failed },
  }
}
