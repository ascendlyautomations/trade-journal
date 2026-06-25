import { formatPublicAccountTypeLabel } from "./publicAccountPrivacy.ts"

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export function isUuidLike(value: unknown): boolean {
  const v = String(value ?? "").trim()
  return v.length > 0 && UUID_RE.test(v)
}

/** User-facing account number — never a database primary key / UUID. */
export function safeAccountNumberLabel(
  value: string | null | undefined
): string | null {
  const v = String(value ?? "").trim()
  if (!v || isUuidLike(v)) return null
  return v
}

/** Display-only: abbreviate balance values ≥1000 as Nk (lowercase k). */
export function formatAccountBalanceForDisplay(size: unknown): string {
  if (size == null || size === "") return ""
  const raw = String(size).trim()
  if (!raw) return ""

  const compact = raw.replace(/,/g, "")

  const kSuffix = /^(\d+(?:\.\d+)?)\s*[kK]$/.exec(compact)
  if (kSuffix) {
    const n = Number(kSuffix[1])
    if (Number.isFinite(n)) {
      return `${formatThousandsInteger(n)}k`
    }
  }

  const numeric = Number(compact.replace(/[$\s]/g, ""))
  if (!Number.isFinite(numeric)) return raw

  if (numeric >= 1000) {
    const thousands = numeric / 1000
    if (Number.isInteger(thousands)) {
      return `${thousands}k`
    }
    const rounded = Math.round(thousands * 10) / 10
    return `${formatThousandsInteger(rounded)}k`
  }

  return raw
}

function formatThousandsInteger(n: number): string {
  return Number.isInteger(n) ? String(n) : String(n).replace(/\.0$/, "")
}

/**
 * If a label ends with a standalone balance number, abbreviate it
 * (e.g. "My Sim 25000" → "My Sim 25k").
 */
export function formatAccountLabelForDisplay(label: string): string {
  const trimmed = String(label ?? "").trim()
  if (!trimmed) return ""

  const match = /^(.*\S)\s+(\d[\d,$\s]*)\s*$/.exec(trimmed)
  if (!match) return trimmed

  const prefix = match[1]
  const formatted = formatAccountBalanceForDisplay(match[2])
  if (formatted !== match[2].trim() && formatted.endsWith("k")) {
    return `${prefix} ${formatted}`
  }

  return trimmed
}

export function formatAccountNameWithSizeDisplay(
  name: string,
  size?: string | null
): string {
  const trimmedName = String(name ?? "").trim()
  const sizePart = formatAccountBalanceForDisplay(size)
  if (trimmedName && sizePart) return `${trimmedName} ${sizePart}`
  if (trimmedName) return formatAccountLabelForDisplay(trimmedName)
  return sizePart
}

export type TradeAccountDisplayInput = {
  account_id?: string | null
  account_name?: string | null
  account_size?: string | null
  account_type?: string | null
  mode?: string | null
  account_number?: string | null
}

export type AccountRowForDisplay = {
  name?: string | null
  account_size?: string | null
  account_number?: string | null
  is_active?: boolean | null
}

/** Prefer linked `accounts.name` over denormalized trade.account_name. */
export function resolveTradeAccountName(
  trade: TradeAccountDisplayInput,
  accountRow?: AccountRowForDisplay | null
): string {
  const fromAccount = String(accountRow?.name ?? "").trim()
  if (fromAccount) return fromAccount
  return String(trade.account_name ?? "").trim()
}

/** Prefer linked `accounts.account_size` over denormalized trade.account_size. */
export function resolveTradeAccountSize(
  trade: TradeAccountDisplayInput,
  accountRow?: AccountRowForDisplay | null
): string {
  const fromAccount =
    accountRow?.account_size != null
      ? String(accountRow.account_size).trim()
      : ""
  if (fromAccount) return fromAccount
  return String(trade.account_size ?? "").trim()
}

export function buildTradeAccountFilterKey(
  trade: TradeAccountDisplayInput,
  accountRow?: AccountRowForDisplay | null
): string {
  const name = resolveTradeAccountName(trade, accountRow)
  const size = resolveTradeAccountSize(trade, accountRow)
  const id = String(trade.account_id ?? "").trim()
  return `${name}|${size}|${id}`
}

export function tradeMatchesAccountFilter(
  trade: TradeAccountDisplayInput,
  accountFilter: string,
  accountRow?: AccountRowForDisplay | null
): boolean {
  if (!accountFilter || accountFilter === "all") return true
  return buildTradeAccountFilterKey(trade, accountRow) === accountFilter
}

/**
 * User-facing trade account line: name → size → type → #account_number.
 * Never includes account_id or other internal IDs.
 */
export function formatTradeAccountDisplay(
  trade: TradeAccountDisplayInput,
  accountRow?: AccountRowForDisplay | null
): string {
  const parts: string[] = []

  const nameSizeLine = formatAccountNameWithSizeDisplay(
    resolveTradeAccountName(trade, accountRow),
    resolveTradeAccountSize(trade, accountRow)
  )
  const type =
    formatPublicAccountTypeLabel(trade.account_type ?? trade.mode) ??
    String(trade.account_type ?? trade.mode ?? "").trim()

  if (nameSizeLine) parts.push(nameSizeLine)
  if (type) parts.push(type)

  const num = safeAccountNumberLabel(
    accountRow?.account_number ?? trade.account_number
  )
  if (num) parts.push(`#${num}`)

  return parts.join(" ").trim()
}

/** Compact "Name Size" line for trade cards. */
export function formatTradeAccountNameSizeLine(
  trade: TradeAccountDisplayInput,
  accountRow?: AccountRowForDisplay | null
): string {
  return formatAccountNameWithSizeDisplay(
    resolveTradeAccountName(trade, accountRow),
    resolveTradeAccountSize(trade, accountRow)
  )
}

export function accountRowForTrade(
  trade: TradeAccountDisplayInput,
  accountById?: Record<string, AccountRowForDisplay | null | undefined> | null
): AccountRowForDisplay | null {
  const id = String(trade.account_id ?? "").trim()
  if (!id || !accountById) return null
  return accountById[id] ?? null
}
