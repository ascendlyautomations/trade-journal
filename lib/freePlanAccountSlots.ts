import type { SupabaseClient } from "@supabase/supabase-js"
import { FREE_PLAN_ACCOUNT_LIMIT } from "@/lib/tradingAccounts"
import { isProActive } from "@/lib/subscription"

export type AccountTradeEntryRow = {
  id?: string | null
  can_add_trades?: boolean | null
}

/** True when the account may receive new trades (default true for legacy rows). */
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

/**
 * Free user must pick up to FREE_PLAN_ACCOUNT_LIMIT entry-enabled accounts
 * when they currently have more than that limit with can_add_trades = true.
 */
export function needsFreePlanAccountSlotSelection(
  profile: Parameters<typeof isProActive>[0],
  accounts: readonly AccountTradeEntryRow[]
): boolean {
  if (isProActive(profile)) return false
  return countTradeEntryEnabledAccounts(accounts) > FREE_PLAN_ACCOUNT_LIMIT
}

/** Accounts allowed in Manual / Quick / CSV / sync pickers. */
export function filterAccountsForTradeEntry<
  T extends AccountTradeEntryRow & { is_active?: boolean | null },
>(accounts: readonly T[]): T[] {
  return accounts.filter(
    (row) => accountCanAddTrades(row) && row.is_active !== false
  )
}

export const ACCOUNT_READ_ONLY_BADGE = "Read Only"

export const ACCOUNT_SLOT_SELECTION_REQUIRED_MESSAGE =
  "Choose up to 3 accounts to keep active for new trades. Your other accounts stay available in read-only mode."

export const ACCOUNT_READ_ONLY_TRADE_MESSAGE =
  "This account is read-only on the Free plan. Choose it as one of your 3 active accounts or upgrade to Pro to add trades."

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
      code: "read_only" | "selection_required" | "missing_account"
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
    .select("id, can_add_trades")
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
    // Legacy trades without a matching accounts row — allow (DB trigger also allows).
    return { ok: true }
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
