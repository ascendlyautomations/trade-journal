import { formatPublicAccountTypeLabel } from "./publicAccountPrivacy"

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

export type TradeAccountDisplayInput = {
  account_name?: string | null
  account_size?: string | null
  account_type?: string | null
  mode?: string | null
  account_number?: string | null
}

/**
 * User-facing trade account line: name → size → type → #account_number.
 * Never includes account_id or other internal IDs.
 */
export function formatTradeAccountDisplay(
  trade: TradeAccountDisplayInput,
  accountRow?: { account_number?: string | null } | null
): string {
  const parts: string[] = []

  const name = String(trade.account_name ?? "").trim()
  const size = String(trade.account_size ?? "").trim()
  const type =
    formatPublicAccountTypeLabel(trade.account_type ?? trade.mode) ??
    String(trade.account_type ?? trade.mode ?? "").trim()

  if (name) parts.push(name)
  if (size) parts.push(size)
  if (type) parts.push(type)

  const num = safeAccountNumberLabel(
    accountRow?.account_number ?? trade.account_number
  )
  if (num) parts.push(`#${num}`)

  return parts.join(" ").trim()
}
