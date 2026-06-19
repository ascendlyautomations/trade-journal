export const ACCOUNT_TYPES = [
  "Personal",
  "Broker",
  "Prop Firm",
  "Backtest",
] as const

export type AccountType = (typeof ACCOUNT_TYPES)[number]

export const ACCOUNT_NAME_EXAMPLES: Record<AccountType, readonly string[]> = {
  Personal: ["Personal Futures", "Personal Options", "Retirement Account"],
  Broker: [
    "Tradovate",
    "NinjaTrader",
    "Interactive Brokers",
    "Charles Schwab",
  ],
  "Prop Firm": ["Apex", "Topstep", "Take Profit Trader", "MyFundedFutures"],
  Backtest: ["ES Backtest", "NQ Strategy Test", "ICT Model Test"],
}

export const ACCOUNT_SIZE_PLACEHOLDER = "Enter account size"

export const ACCOUNT_SIZE_HELPER =
  "Examples: $2,500, $50,000, $150,000"

export function accountNamePlaceholder(type: AccountType): string {
  return `e.g. ${ACCOUNT_NAME_EXAMPLES[type][0]}`
}

export function accountNameHelperText(type: AccountType): string {
  return `Examples: ${ACCOUNT_NAME_EXAMPLES[type].join(", ")}`
}

export function formatAccountSizeInput(value: string): string {
  const cleaned = value.replace(/\D/g, "")
  if (!cleaned) return ""
  const num = Number(cleaned)
  if (!Number.isFinite(num)) return ""
  return num.toLocaleString("en-US")
}

export function parseAccountSizeInput(value: string): string {
  return value.replace(/\D/g, "")
}

export function defaultModeForAccountType(type: AccountType): string {
  if (type === "Prop Firm") return "Eval"
  if (type === "Backtest") return "backtest"
  return "Live"
}

export function showsAccountModeSelector(category: string): boolean {
  return (
    category === "Prop Firm" ||
    category === "Personal" ||
    category === "Broker"
  )
}

export function accountModeOptions(
  category: string
): { value: string; label: string }[] {
  if (category === "Prop Firm") {
    return [
      { value: "Eval", label: "Eval" },
      { value: "Funded", label: "Funded" },
    ]
  }
  return [
    { value: "Live", label: "Live" },
    { value: "Sim", label: "Sim" },
  ]
}

/** Maps UI selections to `accounts.mode` (also used as trade `account_type` when logging). */
export function resolveAccountModeForSave(
  category: string,
  mode: string
): string | null {
  if (category === "Backtest") return "backtest"
  if (category === "Prop Firm") return mode
  if (category === "Personal" || category === "Broker") return mode
  return "Live"
}

export function normalizeAccountCategoryForForm(
  category: string | null | undefined
): AccountType {
  const c = String(category ?? "").trim()
  if ((ACCOUNT_TYPES as readonly string[]).includes(c)) {
    return c as AccountType
  }
  return "Personal"
}

/** Maps stored `accounts.mode` to Create/Edit account form select values. */
export function normalizeAccountModeForForm(
  mode: string | null | undefined,
  category: AccountType
): string {
  const m = String(mode ?? "").trim().toLowerCase()
  if (m === "eval") return "Eval"
  if (m === "funded") return "Funded"
  if (m === "live") return "Live"
  if (m === "sim") return "Sim"
  if (m === "backtest") return "backtest"
  return defaultModeForAccountType(category)
}
