import type { SupabaseClient } from "@supabase/supabase-js"

export type AccountTradeEntryRow = {
  id?: string | null
  can_add_trades?: boolean | null
}

/**
 * Free-plan account-creation quota flag (`can_add_trades = true`).
 * Not trade-entry authorization. Missing values count as enabled for that quota.
 */
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
 * Slot selection used to mark extra accounts read-only. Trade entry no longer
 * uses that picker, so the prompt stays off. Account creation still uses
 * {@link countTradeEntryEnabledAccounts}.
 */
export function needsFreePlanAccountSlotSelection(
  _profile: unknown,
  _accounts: readonly AccountTradeEntryRow[]
): boolean {
  return false
}

/** Active accounts that may receive new trades. Dropdown visibility is separate. */
export function filterAccountsForTradeEntry<
  T extends AccountTradeEntryRow & { is_active?: boolean | null },
>(accounts: readonly T[]): T[] {
  return accounts.filter((row) => row.is_active !== false)
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

/** @deprecated Retired Free-plan read-only UX — do not show in product UI. */
export const ACCOUNT_READ_ONLY_BADGE = "Read Only"

/** @deprecated Retired slot-selection flow. */
export const ACCOUNT_SLOT_SELECTION_REQUIRED_MESSAGE =
  "Choose up to 3 accounts to keep active for new trades."

/** @deprecated Retired read-only trade entry messaging. */
export const ACCOUNT_READ_ONLY_TRADE_MESSAGE =
  "This trading account can't accept new trades right now."

/** Ownership check before inserting a trade. `can_add_trades` is not consulted. */
export async function assertAccountAllowsNewTrades(
  client: SupabaseClient,
  userId: string,
  accountId: string | null | undefined,
  _profile: unknown
): Promise<
  | { ok: true }
  | {
      ok: false
      code: "ownership" | "missing_account"
      message: string
    }
> {
  const id = String(accountId ?? "").trim()
  if (!id) {
    return {
      ok: false,
      code: "missing_account",
      message: "Select a trading account before saving.",
    }
  }

  const { data: target, error } = await client
    .from("accounts")
    .select("id, user_id")
    .eq("id", id)
    .maybeSingle()

  if (error) {
    console.error("[assertAccountAllowsNewTrades]", error)
    return {
      ok: false,
      code: "missing_account",
      message: "Could not verify account access.",
    }
  }

  if (!target) {
    // Legacy trades without a matching accounts row — allow (DB trigger also allows).
    return { ok: true }
  }

  if (String(target.user_id) !== userId) {
    return {
      ok: false,
      code: "ownership",
      message: "That trading account does not belong to you.",
    }
  }

  return { ok: true }
}
