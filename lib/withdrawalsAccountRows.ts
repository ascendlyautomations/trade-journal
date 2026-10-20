import type { SupabaseClient } from "@supabase/supabase-js"
import type { AccountPayoutEntryRecord } from "@/lib/accountPayoutEntry"
import type { PayoutHistoryAccount } from "@/lib/payoutHistory"
import type { AccountPayoutCycle } from "@/lib/propfirmPayoutCycles"

const ACCOUNT_SUMMARY_SELECT = "id,name,mode,category" as const

function mapAccountSummaryRow(
  row: Record<string, unknown>
): PayoutHistoryAccount | null {
  const id = String(row.id ?? "").trim()
  if (!id) return null
  return {
    id,
    name: row.name != null ? String(row.name) : null,
    mode: row.mode,
    category: row.category,
  }
}

/** Merge REST/bootstrap accounts with any account ids referenced by payout rows. */
export async function resolveWithdrawalsAccountRows(
  supabase: SupabaseClient,
  userId: string,
  loadedAccounts: ReadonlyArray<Record<string, unknown>>,
  entries: AccountPayoutEntryRecord[],
  cyclesByAccount: Record<string, AccountPayoutCycle[]>
): Promise<PayoutHistoryAccount[]> {
  const byId = new Map<string, PayoutHistoryAccount>()

  for (const row of loadedAccounts) {
    const mapped = mapAccountSummaryRow(row)
    if (mapped) byId.set(mapped.id, mapped)
  }

  const referenced = new Set<string>()
  for (const entry of entries) {
    if (entry.account_id) referenced.add(entry.account_id)
  }
  for (const cycles of Object.values(cyclesByAccount)) {
    for (const cycle of cycles) {
      if (cycle.account_id) referenced.add(cycle.account_id)
    }
  }

  const missing = [...referenced].filter((id) => !byId.has(id))
  if (missing.length > 0) {
    const { data } = await supabase
      .from("accounts")
      .select(ACCOUNT_SUMMARY_SELECT)
      .eq("user_id", userId)
      .in("id", missing)

    for (const row of data ?? []) {
      const mapped = mapAccountSummaryRow(row as Record<string, unknown>)
      if (mapped) byId.set(mapped.id, mapped)
    }
  }

  for (const id of referenced) {
    if (!byId.has(id)) {
      byId.set(id, { id, name: "Account", mode: null, category: null })
    }
  }

  return [...byId.values()].filter((row) => row.id.length > 0)
}
