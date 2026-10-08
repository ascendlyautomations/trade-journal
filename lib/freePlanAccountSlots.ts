import type { SupabaseClient } from "@supabase/supabase-js"
import { isProActive } from "./subscription.ts"

/** Keep aligned with ``FREE_PLAN_ACCOUNT_LIMIT`` in ``tradingAccounts.ts``. */
export const FREE_PLAN_TRADE_ENTRY_SLOT_LIMIT = 3

export type AccountTradeEntryRow = {
  id?: string | null
  can_add_trades?: boolean | null
}

/** True when the account may receive new trades on Free (default true for legacy rows). */
export function accountCanAddTrades(
  account: AccountTradeEntryRow | null | undefined
): boolean {
  if (!account) return false
  return account.can_add_trades !== false
}

export function countTradeEntryEnabledAccounts(
  accounts: readonly AccountTradeEntryRow[]
): number {
  return accounts.filter((row) => accountCanAddTrades(row)).length
}

/** Every user-created row in `accounts` consumes a Free creation slot. */
export function countTotalTradingAccounts(
  accounts: readonly { id?: string | null }[]
): number {
  return accounts.length
}

/**
 * Free user must pick up to FREE_PLAN_ACCOUNT_LIMIT entry-enabled accounts
 * when they currently have more than that limit with can_add_trades = true.
 */
export function needsFreePlanAccountSlotSelection(
  profile: Parameters<typeof isProActive>[0],
  accounts: readonly AccountTradeEntryRow[]
): boolean {
  if (isProActive(profile)) return false
  return countTradeEntryEnabledAccounts(accounts) > FREE_PLAN_TRADE_ENTRY_SLOT_LIMIT
}

/** Accounts allowed in Manual / Quick / CSV / sync pickers. */
export function filterAccountsForTradeEntry<
  T extends AccountTradeEntryRow & { is_active?: boolean | null },
>(accounts: readonly T[]): T[] {
  return accounts.filter(
    (row) => accountCanAddTrades(row) && row.is_active !== false
  )
}

/** Normal account dropdowns: active and `show_in_account_dropdowns`. */
export function filterAccountsForDropdown<
  T extends AccountTradeEntryRow & {
    is_active?: boolean | null
    show_in_account_dropdowns?: boolean | null
  },
>(accounts: readonly T[]): T[] {
  return filterAccountsForTradeEntry(accounts).filter(
    (row) => row.show_in_account_dropdowns !== false
  )
}

export const ACCOUNT_READ_ONLY_BADGE = "Read Only"

export const ACCOUNT_SLOT_SELECTION_REQUIRED_MESSAGE =
  "Choose up to 3 accounts to keep active for new trades. Your other accounts stay available in read-only mode."

export const ACCOUNT_READ_ONLY_TRADE_MESSAGE =
  "This account is read-only on the Free plan. Choose it as one of your 3 active accounts or upgrade to TraxPro to add trades."

/** Server-side gate before inserting a trade against an accounts row. */
export async function assertAccountAllowsNewTrades(
  client: SupabaseClient,
  userId: string,
  accountId: string | null | undefined,
  profile: Parameters<typeof isProActive>[0]
): Promise<
  | { ok: true }
  | {
      ok: false
      code: "read_only" | "selection_required" | "ownership" | "missing_account"
      message: string
    }
> {
  if (isProActive(profile)) return { ok: true }

  const id = String(accountId ?? "").trim()
  if (!id) {
    return {
      ok: false,
      code: "missing_account",
      message: "Select a trading account before saving.",
    }
  }

  const { data: rows, error } = await client
    .from("accounts")
    .select("id, user_id, can_add_trades")
    .eq("user_id", userId)

  if (error) {
    console.error("[assertAccountAllowsNewTrades]", error)
    return {
      ok: false,
      code: "missing_account",
      message: "Could not verify account access.",
    }
  }

  const accounts = rows ?? []
  if (needsFreePlanAccountSlotSelection(profile, accounts)) {
    return {
      ok: false,
      code: "selection_required",
      message: ACCOUNT_SLOT_SELECTION_REQUIRED_MESSAGE,
    }
  }

  const target = accounts.find((row) => String(row.id) === id)
  if (!target) {
    return { ok: true }
  }

  if (String(target.user_id) !== userId) {
    return {
      ok: false,
      code: "ownership",
      message: "That trading account does not belong to you.",
    }
  }

  if (!accountCanAddTrades(target)) {
    return {
      ok: false,
      code: "read_only",
      message: ACCOUNT_READ_ONLY_TRADE_MESSAGE,
    }
  }

  return { ok: true }
}
