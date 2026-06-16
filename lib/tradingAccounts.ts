import type { SupabaseClient } from "@supabase/supabase-js"
import { isProActive } from "@/lib/subscription"

export type TradingAccountPropFirmRules = {
  consistency: number | null
  maxDrawdown: number | null
  dailyDrawdown: number | null
  profitTarget: number | null
  winningDays: number | null
}

/** Row shape used by Input Trade after `accounts` fetch (settings uses the same mapping). */
export type TradingAccountListItem = {
  name: string
  size: string
  id: string
  account_number: string | null
  mode: string | null
  category: string | null
  is_active: boolean
  note: string
}

export type CreateTradingAccountPayload = {
  name: string
  size: string
  id: string
  category: string
  mode: string | null
  rules: TradingAccountPropFirmRules | null
}

export const FREE_PLAN_ACCOUNT_LIMIT_MESSAGE =
  "Free plan allows only 1 account. Upgrade to Pro to create more."

export function formatTradingAccountSize(size: unknown): string {
  if (!size) return ""
  const num = Number(size)
  if (!Number.isNaN(num) && num >= 1000) {
    return `${num / 1000}K`
  }
  return String(size)
}

export function formatTradingAccountMode(mode: unknown): string | null {
  if (mode == null || String(mode).trim() === "") return null
  const m = String(mode).toLowerCase()
  if (m === "eval") return "Eval"
  if (m === "funded") return "Funded"
  if (m === "live") return "Live"
  if (m === "sim") return "Sim"
  if (m === "backtest") return "Backtest"
  return String(mode)
}

export function tradingAccountDisplayTitle(account: TradingAccountListItem): string {
  const sizePart = formatTradingAccountSize(account.size)
  return sizePart ? `${account.name} ${sizePart}` : account.name
}

function mapAccountRow(acc: Record<string, unknown>): TradingAccountListItem {
  return {
    name: String(acc.name ?? ""),
    size: acc.account_size != null ? String(acc.account_size) : "",
    id: String(acc.id ?? ""),
    account_number:
      acc.account_number != null ? String(acc.account_number) : null,
    mode: acc.mode != null ? String(acc.mode) : null,
    category: acc.category != null ? String(acc.category) : null,
    is_active: acc.is_active !== false,
    note: acc.note != null ? String(acc.note) : "",
  }
}

export function sortTradingAccountsForManagement(
  accounts: TradingAccountListItem[]
): TradingAccountListItem[] {
  return [...accounts].sort((a, b) => {
    if (a.is_active === b.is_active) return 0
    return a.is_active ? -1 : 1
  })
}

export async function loadTradingAccounts(
  client: SupabaseClient,
  userId: string
): Promise<{ accounts: TradingAccountListItem[]; error: Error | null }> {
  const { data, error } = await client
    .from("accounts")
    .select("*")
    .eq("user_id", userId)

  if (error) {
    return { accounts: [], error: new Error(error.message) }
  }

  return {
    accounts: (data ?? []).map((row) =>
      mapAccountRow(row as Record<string, unknown>)
    ),
    error: null,
  }
}

/** Mirrors InputTradeForm free-plan check before insert. */
export async function assertCanCreateTradingAccount(
  client: SupabaseClient,
  userId: string,
  profile: { is_pro?: boolean | null; subscription_status?: string | null } | null
): Promise<{ ok: true } | { ok: false; message: string }> {
  if (isProActive(profile)) {
    return { ok: true }
  }

  const { data: existingAccounts, error: countErr } = await client
    .from("accounts")
    .select("id")
    .eq("user_id", userId)

  if (countErr) {
    console.error(countErr)
    return { ok: false, message: "Something went wrong" }
  }

  if ((existingAccounts ?? []).length >= 1) {
    return { ok: false, message: FREE_PLAN_ACCOUNT_LIMIT_MESSAGE }
  }

  return { ok: true }
}

/** Mirrors InputTradeForm `handleCreateAccountSave` insert payload. */
export async function insertTradingAccount(
  client: SupabaseClient,
  userId: string,
  newAccount: CreateTradingAccountPayload
): Promise<{ account: TradingAccountListItem | null; error: Error | null }> {
  const { data, error } = await client
    .from("accounts")
    .insert([
      {
        user_id: userId,
        name: newAccount.name,
        account_size: newAccount.size,
        account_number: newAccount.id,
        category: newAccount.category,
        mode: newAccount.mode,
        is_active: true,
        consistency: newAccount.rules?.consistency ?? null,
        max_drawdown: newAccount.rules?.maxDrawdown ?? null,
        daily_drawdown: newAccount.rules?.dailyDrawdown ?? null,
        profit_target: newAccount.rules?.profitTarget ?? null,
        winning_days: newAccount.rules?.winningDays ?? null,
      },
    ])
    .select()
    .single()

  if (error) {
    return { account: null, error: new Error(error.message) }
  }

  if (!data) {
    return { account: null, error: new Error("Account was not created") }
  }

  return {
    account: mapAccountRow(data as Record<string, unknown>),
    error: null,
  }
}

/** Mirrors InputTradeForm `toggleAccount` update. */
export async function setTradingAccountActive(
  client: SupabaseClient,
  accountId: string,
  isActive: boolean
): Promise<{ error: Error | null }> {
  const { error } = await client
    .from("accounts")
    .update({ is_active: isActive })
    .eq("id", accountId)

  if (error) {
    return { error: new Error(error.message) }
  }

  return { error: null }
}

/** Mirrors InputTradeForm `updateNote` — `accounts.note`, empty string → null. */
export async function updateTradingAccountNote(
  client: SupabaseClient,
  accountId: string,
  note: string
): Promise<{ error: Error | null }> {
  const { error } = await client
    .from("accounts")
    .update({ note: note || null })
    .eq("id", accountId)

  if (error) {
    return { error: new Error(error.message) }
  }

  return { error: null }
}
