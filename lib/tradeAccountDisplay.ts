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
  id?: string | null
  name?: string | null
  account_size?: string | null
  account_number?: string | null
  mode?: string | null
  is_active?: boolean | null
  can_add_trades?: boolean | null
}

export type AccountFilterOption = {
  value: string
  label: string
  /** Name/size segment — truncate this when space is tight. */
  labelName?: string
  /** Fixed suffix (` • #ID • Mode`) — do not truncate. */
  labelSuffix?: string
  accountType?: string | null
  /** Free-plan historical account — shown in filters, not trade-entry pickers. */
  readOnly?: boolean
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

/** Filter key for an account row (`name|size|accountId`). */
export function buildAccountFilterKeyFromRow(
  accountRow: AccountRowForDisplay
): string {
  const name = String(accountRow.name ?? "").trim()
  const size =
    accountRow.account_size != null
      ? String(accountRow.account_size).trim()
      : ""
  const id = String(accountRow.id ?? "").trim()
  return `${name}|${size}|${id}`
}

/**
 * Mode badge for account selectors (Eval / Funded / Live / …).
 */
export function formatTradingAccountModeLabel(mode: unknown): string {
  if (mode == null || String(mode).trim() === "") return "Live"
  const m = String(mode).toLowerCase().trim()
  if (m === "eval") return "Eval"
  if (m === "funded") return "Funded"
  if (m === "live") return "Live"
  if (m === "sim") return "Sim"
  if (m === "backtest") return "Backtest"
  return String(mode).trim()
}

export type TradingAccountSelectorLabelInput = {
  name?: string | null
  size?: string | null
  account_size?: string | null
  account_number?: string | null
  mode?: string | null
}

/**
 * Selector label parts: truncate `name` only; keep `suffix` (` • #ID • Mode`) fully visible.
 */
export function formatTradingAccountSelectorParts(
  account: TradingAccountSelectorLabelInput,
  options?: { includeAccountNumber?: boolean }
): { name: string; suffix: string } {
  const name = formatAccountNameWithSizeDisplay(
    account.name ?? "",
    account.size ?? account.account_size ?? null
  )
  const tail: string[] = []
  if (options?.includeAccountNumber !== false) {
    const num = safeAccountNumberLabel(account.account_number)
    if (num) tail.push(`#${num}`)
  }
  const modeLabel = formatTradingAccountModeLabel(account.mode)
  if (modeLabel) tail.push(modeLabel)
  const suffix = tail.length > 0 ? ` • ${tail.join(" • ")}` : ""
  return { name, suffix }
}

/**
 * Account dropdown label: Account Name • Account ID • Eval/Funded.
 * Account ID always appears before mode when present.
 */
export function formatTradingAccountSelectorLabel(
  account: TradingAccountSelectorLabelInput,
  options?: { includeAccountNumber?: boolean }
): string {
  const { name, suffix } = formatTradingAccountSelectorParts(account, options)
  return `${name}${suffix}`.replace(/\s+/g, " ").trim()
}

/**
 * Build account selector options from `accounts` rows for historical filters.
 * Includes read-only (can_add_trades = false) accounts with a badge flag.
 * Soft-hidden (`is_active === false`) rows remain available for history.
 */
export function buildAccountFilterOptionsFromRows(
  accountRows: readonly AccountRowForDisplay[],
  options?: { includeAccountNumberInLabel?: boolean }
): AccountFilterOption[] {
  const includeAccountNumber = options?.includeAccountNumberInLabel !== false
  const accountMap = new Map<string, AccountFilterOption>()

  for (const row of accountRows) {
    const id = String(row.id ?? "").trim()
    const name = String(row.name ?? "").trim()
    if (!id || !name) continue

    const value = buildAccountFilterKeyFromRow(row)
    if (accountMap.has(value)) continue

    const parts = formatTradingAccountSelectorParts(
      {
        name: row.name,
        account_size: row.account_size,
        account_number: row.account_number,
        mode: row.mode,
      },
      { includeAccountNumber }
    )

    const readOnly = row.can_add_trades === false
    const baseLabel = `${parts.name}${parts.suffix}`.replace(/\s+/g, " ").trim()

    accountMap.set(value, {
      value,
      label: readOnly ? `${baseLabel} (Read Only)` : baseLabel,
      labelName: parts.name,
      labelSuffix: readOnly
        ? `${parts.suffix} • Read Only`
        : parts.suffix,
      accountType: row.mode ?? null,
      readOnly,
    })
  }

  return Array.from(accountMap.values())
}

export function tradeMatchesAccountFilter(
  trade: TradeAccountDisplayInput,
  accountFilter: string,
  accountRow?: AccountRowForDisplay | null,
  options?: { copyGroupAccountIds?: readonly string[] }
): boolean {
  if (!accountFilter || accountFilter === "all") return true

  if (options?.copyGroupAccountIds && options.copyGroupAccountIds.length > 0) {
    const tradeAccountId = String(trade.account_id ?? "").trim()
    return options.copyGroupAccountIds.includes(tradeAccountId)
  }

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
