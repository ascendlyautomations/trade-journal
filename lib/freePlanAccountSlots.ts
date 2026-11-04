import type { SupabaseClient } from "@supabase/supabase-js"
import { isProActive, isProActiveForTradeSlots } from "./subscription.ts"

export type FreePlanTradeSlotsEpoch = {
  required: number
  confirmed: number
}

export function parseFreePlanTradeSlotsEpoch(
  profile:
    | {
        free_plan_trade_slots_epoch?: number | string | null
        free_plan_trade_slots_confirmed_epoch?: number | string | null
        [key: string]: unknown
      }
    | null
    | undefined
): FreePlanTradeSlotsEpoch {
  const required = Number(profile?.free_plan_trade_slots_epoch ?? 0)
  const confirmed = Number(profile?.free_plan_trade_slots_confirmed_epoch ?? 0)
  return {
    required: Number.isFinite(required) ? required : 0,
    confirmed: Number.isFinite(confirmed) ? confirmed : 0,
  }
}

/** True when a new downgrade requires the 3-account picker (>3 accounts owned). */
export function freePlanTradeSlotsPending(
  totalAccounts: number,
  epochs: FreePlanTradeSlotsEpoch
): boolean {
  if (totalAccounts <= FREE_PLAN_TRADE_ENTRY_SLOT_LIMIT) return false
  return epochs.confirmed < epochs.required
}

/** Keep aligned with ``FREE_PLAN_ACCOUNT_LIMIT`` in ``tradingAccounts.ts``. */
export const FREE_PLAN_TRADE_ENTRY_SLOT_LIMIT = 3

export type AccountTradeEntryRow = {
  id?: string | null
  can_add_trades?: boolean | null
}

/** True when the account is an active Free trade-entry slot (explicit true only). */
export function accountCanAddTrades(
  account: AccountTradeEntryRow | null | undefined
): boolean {
  if (!account) return false
  return account.can_add_trades === true
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
  profile: Parameters<typeof isProActiveForTradeSlots>[0],
  accounts: readonly AccountTradeEntryRow[],
  epochs?: FreePlanTradeSlotsEpoch
): boolean {
  if (isProActiveForTradeSlots(profile)) return false
  const total = countTotalTradingAccounts(accounts)
  if (epochs && freePlanTradeSlotsPending(total, epochs)) return true
  return countTradeEntryEnabledAccounts(accounts) > FREE_PLAN_TRADE_ENTRY_SLOT_LIMIT
}

/**
 * Automatic picker. `null` means the entitlement is still loading or unknown
 * and must not be treated as Free.
 */
export function freePlanSlotSelectionRequired(
  traxProActive: boolean | null,
  accounts: readonly AccountTradeEntryRow[],
  epochs?: FreePlanTradeSlotsEpoch
): boolean {
  if (traxProActive !== false) return false
  const total = countTotalTradingAccounts(accounts)
  if (total <= FREE_PLAN_TRADE_ENTRY_SLOT_LIMIT) return false
  if (epochs && freePlanTradeSlotsPending(total, epochs)) return true
  return countTradeEntryEnabledAccounts(accounts) > FREE_PLAN_TRADE_ENTRY_SLOT_LIMIT
}

/** Ids already saved with can_add_trades = true, when that set is a valid 1–3 pick. */
export function persistedTradeEntrySelectionIds(
  accounts: readonly AccountTradeEntryRow[]
): string[] {
  const ids = accounts
    .filter((row) => row.can_add_trades === true && String(row.id ?? "").trim())
    .map((row) => String(row.id))
  if (ids.length < 1 || ids.length > FREE_PLAN_TRADE_ENTRY_SLOT_LIMIT) return []
  return ids
}

/** Accounts allowed in Manual / Quick / CSV / sync pickers. */
export function filterAccountsForTradeEntry<
  T extends AccountTradeEntryRow & {
    is_active?: boolean | null
    show_in_account_dropdowns?: boolean | null
  },
>(accounts: readonly T[]): T[] {
  return accounts.filter(
    (row) =>
      accountCanAddTrades(row) &&
      row.is_active !== false &&
      row.show_in_account_dropdowns !== false
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

export const ACCOUNT_VIEW_ONLY_BADGE = "View Only"

/** @deprecated Use ACCOUNT_VIEW_ONLY_BADGE */
export const ACCOUNT_READ_ONLY_BADGE = ACCOUNT_VIEW_ONLY_BADGE

export const ACCOUNT_SLOT_SELECTION_REQUIRED_MESSAGE =
  "Choose up to 3 accounts to keep active for new trades. Your other accounts stay available in view-only mode."

export const ACCOUNT_READ_ONLY_TRADE_MESSAGE =
  "This account is view-only on the Free plan. Choose it as one of your 3 active accounts or upgrade to TraxPro to add or edit trades."

export const COPY_TRADING_ACCOUNT_READ_ONLY_TRADE_MESSAGE =
  "This account is linked to Copy Trading and stays view-only on the Free plan. Upgrade to TraxPro to journal new trades here."

/** Client-side gate before any trade write (insert, update, delete) on an account. */
export async function assertAccountAllowsTradeWrites(
  client: SupabaseClient,
  userId: string,
  accountId: string | null | undefined,
  profile: Parameters<typeof isProActiveForTradeSlots>[0],
  knownTraxProActive?: boolean | null
): Promise<
  | { ok: true }
  | {
      ok: false
      code: "read_only" | "selection_required" | "ownership" | "missing_account"
      message: string
    }
> {
  return assertAccountAllowsNewTrades(
    client,
    userId,
    accountId,
    profile,
    knownTraxProActive
  )
}

/** Server-side gate before inserting a trade against an accounts row. */
export async function assertAccountAllowsNewTrades(
  client: SupabaseClient,
  userId: string,
  accountId: string | null | undefined,
  profile: Parameters<typeof isProActiveForTradeSlots>[0],
  knownTraxProActive?: boolean | null
): Promise<
  | { ok: true }
  | {
      ok: false
      code: "read_only" | "selection_required" | "ownership" | "missing_account"
      message: string
    }
> {
  if (
    knownTraxProActive === true ||
    (knownTraxProActive == null && isProActiveForTradeSlots(profile))
  ) {
    return { ok: true }
  }

  const id = String(accountId ?? "").trim()
  if (!id) {
    return {
      ok: false,
      code: "missing_account",
      message: "Select a trading account before saving.",
    }
  }

  const [{ data: rows, error }, { data: profileRow }] = await Promise.all([
    client
      .from("accounts")
      .select("id, user_id, can_add_trades")
      .eq("user_id", userId),
    client
      .from("profiles")
      .select(
        "free_plan_trade_slots_epoch, free_plan_trade_slots_confirmed_epoch, is_pro, creator_access, subscription_status, trial_end, early_access_enrolled_at, early_access_started_at, early_access_status, early_access_ends_at, early_access_campaign_id, early_access_enrollment_source"
      )
      .eq("id", userId)
      .maybeSingle(),
  ])

  if (error) {
    console.error("[assertAccountAllowsNewTrades]", error)
    return {
      ok: false,
      code: "missing_account",
      message: "Could not verify account access.",
    }
  }

  const accounts = rows ?? []
  const epochs = parseFreePlanTradeSlotsEpoch(profileRow ?? profile)
  const gateProfile = profileRow ?? profile
  if (needsFreePlanAccountSlotSelection(gateProfile, accounts, epochs)) {
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

  if (target.can_add_trades !== true) {
    return {
      ok: false,
      code: "read_only",
      message: ACCOUNT_READ_ONLY_TRADE_MESSAGE,
    }
  }

  return { ok: true }
}
