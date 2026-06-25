import type { SupabaseClient } from "@supabase/supabase-js"
import { isProActive } from "@/lib/subscription"
import {
  normalizeAccountCategoryForForm,
  normalizeAccountModeForForm,
  type AccountType,
} from "@/lib/createAccountForm"
import {
  formatAccountBalanceForDisplay,
  formatAccountNameWithSizeDisplay,
} from "@/lib/tradeAccountDisplay"

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
  rules: TradingAccountPropFirmRules | null
}

export type AccountFormInitialValues = {
  name: string
  size: string
  accountNumber: string
  category: AccountType
  mode: string
  rules: TradingAccountPropFirmRules | null
}

export type CreateTradingAccountPayload = {
  name: string
  size: string
  id: string
  category: string
  mode: string | null
  rules: TradingAccountPropFirmRules | null
}

export const FREE_PLAN_ACCOUNT_LIMIT = 3

export const FREE_PLAN_ACCOUNT_LIMIT_MESSAGE =
  "Free plan allows up to 3 accounts. Upgrade to Pro for unlimited accounts."

export function formatTradingAccountSize(size: unknown): string {
  return formatAccountBalanceForDisplay(size)
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
  return formatAccountNameWithSizeDisplay(account.name, account.size)
}

function mapPropFirmRules(
  acc: Record<string, unknown>
): TradingAccountPropFirmRules {
  const num = (value: unknown) =>
    value != null && value !== "" && !Number.isNaN(Number(value))
      ? Number(value)
      : null

  return {
    consistency: num(acc.consistency),
    maxDrawdown: num(acc.max_drawdown),
    dailyDrawdown: num(acc.daily_drawdown),
    profitTarget: num(acc.profit_target),
    winningDays: num(acc.winning_days),
  }
}

function mapAccountRow(acc: Record<string, unknown>): TradingAccountListItem {
  const category = acc.category != null ? String(acc.category) : null
  return {
    name: String(acc.name ?? ""),
    size: acc.account_size != null ? String(acc.account_size) : "",
    id: String(acc.id ?? ""),
    account_number:
      acc.account_number != null ? String(acc.account_number) : null,
    mode: acc.mode != null ? String(acc.mode) : null,
    category,
    is_active: acc.is_active !== false,
    note: acc.note != null ? String(acc.note) : "",
    rules: category === "Prop Firm" ? mapPropFirmRules(acc) : null,
  }
}

export function tradingAccountToFormValues(
  account: TradingAccountListItem
): AccountFormInitialValues {
  const category = normalizeAccountCategoryForForm(account.category)
  return {
    name: account.name,
    size: account.size.replace(/\D/g, ""),
    accountNumber: account.account_number ?? "",
    category,
    mode: normalizeAccountModeForForm(account.mode, category),
    rules: account.rules,
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

  if ((existingAccounts ?? []).length >= FREE_PLAN_ACCOUNT_LIMIT) {
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
    if (error.code === "23505") {
      return {
        account: null,
        error: new Error("An account with this name already exists"),
      }
    }
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

function mergePropFirmRules(
  next: TradingAccountPropFirmRules | null,
  previous: TradingAccountPropFirmRules | null
): TradingAccountPropFirmRules | null {
  if (!next) return null
  return {
    consistency: next.consistency ?? previous?.consistency ?? null,
    maxDrawdown: next.maxDrawdown ?? previous?.maxDrawdown ?? null,
    dailyDrawdown: next.dailyDrawdown ?? previous?.dailyDrawdown ?? null,
    profitTarget: next.profitTarget ?? previous?.profitTarget ?? null,
    winningDays: next.winningDays ?? previous?.winningDays ?? null,
  }
}

/** Updates an existing account row — owner-only via RLS + user_id filter. */
export async function updateTradingAccount(
  client: SupabaseClient,
  userId: string,
  accountId: string,
  payload: CreateTradingAccountPayload,
  previous: TradingAccountListItem
): Promise<{ account: TradingAccountListItem | null; error: Error | null }> {
  const name = payload.name.trim()
  if (!name) {
    return { account: null, error: new Error("Account name is required") }
  }

  const accountSize = payload.size.trim() ? payload.size : previous.size
  const accountNumber = payload.id.trim()
    ? payload.id.trim()
    : (previous.account_number ?? "")

  const rules =
    payload.category === "Prop Firm"
      ? mergePropFirmRules(payload.rules, previous.rules)
      : null

  const { data, error } = await client
    .from("accounts")
    .update({
      name,
      account_size: accountSize || null,
      account_number: accountNumber || null,
      category: payload.category,
      mode: payload.mode,
      consistency: rules?.consistency ?? null,
      max_drawdown: rules?.maxDrawdown ?? null,
      daily_drawdown: rules?.dailyDrawdown ?? null,
      profit_target: rules?.profitTarget ?? null,
      winning_days: rules?.winningDays ?? null,
    })
    .eq("id", accountId)
    .eq("user_id", userId)
    .select()
    .single()

  if (error) {
    if (error.code === "23505") {
      return {
        account: null,
        error: new Error("An account with this name already exists"),
      }
    }
    return { account: null, error: new Error(error.message) }
  }

  if (!data) {
    return { account: null, error: new Error("Account was not updated") }
  }

  const syncError = await syncTradesAfterAccountRename(client, userId, accountId, {
    name,
    account_size: accountSize || null,
  })
  if (syncError) {
    return { account: null, error: syncError }
  }

  return {
    account: mapAccountRow(data as Record<string, unknown>),
    error: null,
  }
}

/** Keep denormalized trade fields aligned when an account is renamed. */
export async function syncTradesAfterAccountRename(
  client: SupabaseClient,
  userId: string,
  accountId: string,
  fields: { name: string; account_size: string | null }
): Promise<Error | null> {
  const tradeUpdate: Record<string, string | null> = {
    account_name: fields.name,
  }
  if (fields.account_size != null && fields.account_size !== "") {
    tradeUpdate.account_size = fields.account_size
  }

  const { error: tradesErr } = await client
    .from("trades")
    .update(tradeUpdate)
    .eq("user_id", userId)
    .eq("account_id", accountId)

  if (tradesErr) {
    return new Error(tradesErr.message)
  }

  const profileUpdate: Record<string, string | null> = {
    locked_account_name: fields.name,
  }
  if (fields.account_size != null && fields.account_size !== "") {
    profileUpdate.locked_account_size = fields.account_size
  }

  const { error: profileErr } = await client
    .from("profiles")
    .update(profileUpdate)
    .eq("id", userId)
    .eq("locked_account_id", accountId)

  if (profileErr) {
    return new Error(profileErr.message)
  }

  return null
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
