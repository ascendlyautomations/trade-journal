import type { SupabaseClient } from "@supabase/supabase-js"
import type {
  PayoutDrawdownBehavior,
  PropfirmEquityPayoutEventInput,
  PropfirmPayoutCycleContext,
} from "./propfirmMetrics"

export type AccountPayoutCycle = {
  id: string
  account_id: string
  started_at: string
  ended_at: string | null
  cycle_start_balance: number
  payout_amount: number | null
  note: string | null
  balance_before_payout: number | null
  balance_after_payout: number | null
  drawdown_behavior: PayoutDrawdownBehavior | null
  drawdown_floor_after_payout: number | null
  cycle_number: number | null
}

export type RecordAccountPayoutInput = {
  balanceAfterPayout: number
  payoutAmount: number
  drawdownBehavior: PayoutDrawdownBehavior
  drawdownFloorAfterPayout: number
  balanceBeforePayout: number
  rememberDrawdownBehavior: boolean
}

export type RecordAccountPayoutResult = {
  cycle: AccountPayoutCycle | null
  accountPreferences: {
    payout_drawdown_behavior: PayoutDrawdownBehavior | null
    remember_payout_drawdown_behavior: boolean
  } | null
  error: string | null
}

/** Payout details collected before achievement save — applied only after achievement succeeds. */
export type PendingPropFirmPayoutRecord = {
  accountId: string
  input: RecordAccountPayoutInput
  nextCycleNumber: number
}

const PAYOUT_CYCLE_FIELDS =
  "id,account_id,started_at,ended_at,cycle_start_balance,payout_amount,note,balance_before_payout,balance_after_payout,drawdown_behavior,drawdown_floor_after_payout,cycle_number"

function mapPayoutCycleRow(row: Record<string, unknown>): AccountPayoutCycle {
  const drawdownBehavior = row.drawdown_behavior
  return {
    id: String(row.id ?? ""),
    account_id: String(row.account_id ?? ""),
    started_at: String(row.started_at ?? ""),
    ended_at: row.ended_at != null ? String(row.ended_at) : null,
    cycle_start_balance: Number(row.cycle_start_balance) || 0,
    payout_amount:
      row.payout_amount != null && row.payout_amount !== ""
        ? Number(row.payout_amount)
        : null,
    note: row.note != null ? String(row.note) : null,
    balance_before_payout:
      row.balance_before_payout != null && row.balance_before_payout !== ""
        ? Number(row.balance_before_payout)
        : null,
    balance_after_payout:
      row.balance_after_payout != null && row.balance_after_payout !== ""
        ? Number(row.balance_after_payout)
        : null,
    drawdown_behavior:
      drawdownBehavior === "reset_to_account" ||
      drawdownBehavior === "keep_trailing"
        ? drawdownBehavior
        : null,
    drawdown_floor_after_payout:
      row.drawdown_floor_after_payout != null &&
      row.drawdown_floor_after_payout !== ""
        ? Number(row.drawdown_floor_after_payout)
        : null,
    cycle_number:
      row.cycle_number != null && row.cycle_number !== ""
        ? Number(row.cycle_number)
        : null,
  }
}

/** Active (open) payout cycle for an account, if any. */
export async function fetchActivePayoutCycle(
  supabase: SupabaseClient,
  accountId: string | number
): Promise<AccountPayoutCycle | null> {
  const { data, error } = await supabase
    .from("account_payout_cycles")
    .select(PAYOUT_CYCLE_FIELDS)
    .eq("account_id", accountId)
    .is("ended_at", null)
    .order("started_at", { ascending: false })
    .limit(1)
    .maybeSingle()

  if (error) {
    console.error("fetchActivePayoutCycle", error)
    return null
  }

  return data ? mapPayoutCycleRow(data as Record<string, unknown>) : null
}

/** Payout history for future analytics surfaces (newest first). */
export async function fetchPayoutCycleHistory(
  supabase: SupabaseClient,
  accountId: string | number
): Promise<AccountPayoutCycle[]> {
  const { data, error } = await supabase
    .from("account_payout_cycles")
    .select(PAYOUT_CYCLE_FIELDS)
    .eq("account_id", accountId)
    .order("started_at", { ascending: false })

  if (error) {
    console.error("fetchPayoutCycleHistory", error)
    return []
  }

  return (data ?? []).map((row) =>
    mapPayoutCycleRow(row as Record<string, unknown>)
  )
}

/** Open payout cycle from a cached history list. */
export function selectActivePayoutCycle(
  cycles: AccountPayoutCycle[]
): AccountPayoutCycle | null {
  return cycles.find((cycle) => cycle.ended_at == null) ?? null
}

/** Completed payouts for dashboard totals (closed cycles with a payout amount). */
export function summarizeAccountPayouts(cycles: AccountPayoutCycle[]): {
  count: number
  totalAmount: number
} {
  return cycles.reduce(
    (summary, cycle) => {
      if (
        cycle.ended_at != null &&
        cycle.payout_amount != null &&
        cycle.payout_amount > 0
      ) {
        summary.count += 1
        summary.totalAmount += cycle.payout_amount
      }
      return summary
    },
    { count: 0, totalAmount: 0 }
  )
}

function isCompletedPayoutCycle(cycle: AccountPayoutCycle): boolean {
  return (
    cycle.ended_at != null &&
    cycle.payout_amount != null &&
    cycle.payout_amount > 0
  )
}

/** Completed payout history for UI (newest first; excludes active open cycle). */
export function selectCompletedPayoutHistory(
  cycles: AccountPayoutCycle[]
): AccountPayoutCycle[] {
  return cycles
    .filter(isCompletedPayoutCycle)
    .sort(
      (left, right) =>
        new Date(String(right.ended_at)).getTime() -
        new Date(String(left.ended_at)).getTime()
    )
}

export function formatPayoutDrawdownBehaviorLabel(
  behavior: PayoutDrawdownBehavior | null | undefined
): string {
  if (behavior === "keep_trailing") return "Trailing Drawdown Continues"
  if (behavior === "reset_to_account") return "Resets To Starting Balance"
  return "—"
}

export function formatPayoutHistoryDate(iso: string | null | undefined): string {
  if (!iso) return "—"
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return "—"
  return date.toLocaleDateString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
  })
}

export type RecordedPayoutSnapshot = {
  amount: number
  balanceBefore: number
  balanceAfter: number
  drawdownBehavior: PayoutDrawdownBehavior
  drawdownFloor: number
  recordedAt: string
  cycleNumber: number
}

/** Update cached payout history after Record Payout (no refetch). */
export function applyRecordedPayoutToHistory(
  previousCycles: AccountPayoutCycle[],
  previousActive: AccountPayoutCycle | null,
  newActive: AccountPayoutCycle,
  payout: RecordedPayoutSnapshot
): AccountPayoutCycle[] {
  const closedPayout: AccountPayoutCycle = previousActive
    ? {
        ...previousActive,
        ended_at: payout.recordedAt,
        payout_amount: payout.amount,
        balance_before_payout: payout.balanceBefore,
        balance_after_payout: payout.balanceAfter,
        drawdown_behavior: payout.drawdownBehavior,
        drawdown_floor_after_payout: payout.drawdownFloor,
        cycle_number: payout.cycleNumber,
      }
    : {
        id: `${newActive.id}-recorded-payout`,
        account_id: newActive.account_id,
        started_at: payout.recordedAt,
        ended_at: payout.recordedAt,
        cycle_start_balance: payout.balanceBefore,
        payout_amount: payout.amount,
        note: null,
        balance_before_payout: payout.balanceBefore,
        balance_after_payout: payout.balanceAfter,
        drawdown_behavior: payout.drawdownBehavior,
        drawdown_floor_after_payout: payout.drawdownFloor,
        cycle_number: payout.cycleNumber,
      }

  const withoutStale = previousCycles.filter(
    (cycle) =>
      cycle.id !== previousActive?.id &&
      cycle.id !== newActive.id &&
      cycle.id !== closedPayout.id
  )

  return [newActive, closedPayout, ...withoutStale]
}

export function buildPayoutCycleContext(
  activeCycle: AccountPayoutCycle | null,
  accountStartingBalance: number
): PropfirmPayoutCycleContext {
  if (!activeCycle) {
    return {
      startedAt: null,
      cycleStartBalance: accountStartingBalance,
    }
  }

  return {
    startedAt: activeCycle.started_at,
    cycleStartBalance: activeCycle.cycle_start_balance,
    initialDrawdownFloor: activeCycle.drawdown_floor_after_payout,
    drawdownBehavior: activeCycle.drawdown_behavior,
    cycleNumber: activeCycle.cycle_number,
  }
}

/** Build the open cycle locally after Record Payout (avoids a follow-up fetch). */
export function createActivePayoutCycleLocal(
  accountId: string | number,
  input: RecordAccountPayoutInput,
  cycleId: string,
  startedAt: string,
  cycleNumber: number | null
): AccountPayoutCycle {
  return {
    id: cycleId,
    account_id: String(accountId),
    started_at: startedAt,
    ended_at: null,
    cycle_start_balance: input.balanceAfterPayout,
    payout_amount: null,
    note: null,
    balance_before_payout: null,
    balance_after_payout: input.balanceAfterPayout,
    drawdown_behavior: input.drawdownBehavior,
    drawdown_floor_after_payout: input.drawdownFloorAfterPayout,
    cycle_number: cycleNumber,
  }
}

export async function recordAccountPayout(
  supabase: SupabaseClient,
  accountId: string | number,
  input: RecordAccountPayoutInput,
  nextCycleNumber: number
): Promise<RecordAccountPayoutResult> {
  const startedAt = new Date().toISOString()

  const { data, error } = await supabase.rpc("record_account_payout", {
    p_account_id: accountId,
    p_balance_after_payout: input.balanceAfterPayout,
    p_payout_amount: input.payoutAmount,
    p_drawdown_behavior: input.drawdownBehavior,
    p_drawdown_floor_after_payout: input.drawdownFloorAfterPayout,
    p_balance_before_payout: input.balanceBeforePayout,
    p_remember_drawdown_behavior: input.rememberDrawdownBehavior,
  })

  if (error) {
    console.error("recordAccountPayout", error)
    return { cycle: null, accountPreferences: null, error: error.message }
  }

  if (data == null) {
    return {
      cycle: null,
      accountPreferences: null,
      error: "Payout cycle was not created",
    }
  }

  return {
    cycle: createActivePayoutCycleLocal(
      accountId,
      input,
      String(data),
      startedAt,
      nextCycleNumber
    ),
    accountPreferences: input.rememberDrawdownBehavior
      ? {
          payout_drawdown_behavior: input.drawdownBehavior,
          remember_payout_drawdown_behavior: true,
        }
      : null,
    error: null,
  }
}

export function isFundedPropfirmAccount(mode: unknown): boolean {
  return String(mode ?? "").trim().toLowerCase() === "funded"
}

export function isEvalPropfirmAccount(mode: unknown): boolean {
  return String(mode ?? "").trim().toLowerCase() === "eval"
}

export const PROPFIRM_ALL_ACCOUNTS_VALUE = "all"

export type PayoutHistoryEntry = AccountPayoutCycle & {
  accountName: string
}

/** Load payout cycles for many accounts in one set-based query (funded accounts only). */
export async function fetchPayoutCycleHistoryByAccountIds(
  supabase: SupabaseClient,
  accountIds: Array<string | number>
): Promise<Record<string, AccountPayoutCycle[]>> {
  const uniqueIds = [
    ...new Set(accountIds.map((id) => String(id).trim()).filter(Boolean)),
  ]
  if (uniqueIds.length === 0) return {}

  const { data, error } = await supabase
    .from("account_payout_cycles")
    .select(PAYOUT_CYCLE_FIELDS)
    .in("account_id", uniqueIds)
    .order("started_at", { ascending: false })

  if (error) {
    console.error("fetchPayoutCycleHistoryByAccountIds", error)
    return Object.fromEntries(uniqueIds.map((id) => [id, [] as AccountPayoutCycle[]]))
  }

  const grouped: Record<string, AccountPayoutCycle[]> = Object.fromEntries(
    uniqueIds.map((id) => [id, [] as AccountPayoutCycle[]])
  )
  for (const row of data ?? []) {
    const mapped = mapPayoutCycleRow(row as Record<string, unknown>)
    const accountId = mapped.account_id
    if (!grouped[accountId]) grouped[accountId] = []
    grouped[accountId].push(mapped)
  }
  return grouped
}

/** Merge completed payouts across funded accounts (newest first). */
export function mergeFundedPayoutHistory(
  accounts: Array<{ id: string | number; name?: string | null; account_size?: unknown }>,
  cyclesByAccountId: Record<string, AccountPayoutCycle[]>,
  formatAccountLabel: (account: {
    name?: string | null
    account_size?: unknown
  }) => string
): PayoutHistoryEntry[] {
  const rows: PayoutHistoryEntry[] = []

  for (const account of accounts) {
    if (!isFundedPropfirmAccount((account as { mode?: unknown }).mode)) continue
    const accountId = String(account.id)
    const accountName = formatAccountLabel(account)
    for (const cycle of selectCompletedPayoutHistory(
      cyclesByAccountId[accountId] ?? []
    )) {
      rows.push({ ...cycle, accountName })
    }
  }

  return rows.sort(
    (left, right) =>
      new Date(String(right.ended_at)).getTime() -
      new Date(String(left.ended_at)).getTime()
  )
}

/** Strip trailing account size from a prop firm account name for display defaults. */
export function inferPropFirmName(accountName: string | null | undefined): string {
  const name = String(accountName ?? "").trim()
  if (!name) return ""
  const withoutSize = name
    .replace(/\s+\$?[\d,]+(?:\.\d+)?\s*[kK]?$/i, "")
    .trim()
  return withoutSize || name
}

export function resolveDefaultPayoutDrawdownBehavior(
  account:
    | {
        payout_drawdown_behavior?: string | null
        remember_payout_drawdown_behavior?: boolean | null
      }
    | null
    | undefined,
  activeCycle: AccountPayoutCycle | null
): PayoutDrawdownBehavior {
  if (
    account?.remember_payout_drawdown_behavior &&
    (account.payout_drawdown_behavior === "reset_to_account" ||
      account.payout_drawdown_behavior === "keep_trailing")
  ) {
    return account.payout_drawdown_behavior
  }

  if (
    activeCycle?.drawdown_behavior === "reset_to_account" ||
    activeCycle?.drawdown_behavior === "keep_trailing"
  ) {
    return activeCycle.drawdown_behavior
  }

  return "reset_to_account"
}

/** Completed payouts as equity-curve withdrawal events (newest first in source list). */
export function selectRecordedPayoutEquityEvents(
  cycles: AccountPayoutCycle[]
): PropfirmEquityPayoutEventInput[] {
  return cycles
    .filter(
      (cycle) =>
        cycle.ended_at != null &&
        cycle.payout_amount != null &&
        cycle.payout_amount > 0
    )
    .map((cycle) => ({
      endedAt: String(cycle.ended_at),
      amount: Number(cycle.payout_amount),
    }))
    .sort(
      (left, right) =>
        new Date(left.endedAt).getTime() - new Date(right.endedAt).getTime()
    )
}
