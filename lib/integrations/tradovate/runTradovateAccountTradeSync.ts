import type { SupabaseClient } from "@supabase/supabase-js"
import { loadBrokerAccountSyncViews } from "@/lib/integrations/brokerIntegrationSync"
import {
  syncTradovateBrokerAccount,
  type TradovateSyncSummary,
} from "@/lib/integrations/tradovate/syncTradovateBrokerAccount"

export type { TradovateSyncSummary } from "@/lib/integrations/tradovate/syncTradovateBrokerAccount"

/** @deprecated Prefer syncTradovateBrokerAccount — kept for existing imports. */
export async function runTradovateAccountTradeSync(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string,
  mappingId: string
): Promise<TradovateSyncSummary> {
  return syncTradovateBrokerAccount(supabase, {
    userId,
    connectionId,
    brokerIntegrationAccountId: mappingId,
    trigger: "manual",
  })
}

export async function attachSyncViewsToBrokerAccounts<
  T extends { id: string }
>(
  supabase: SupabaseClient,
  accounts: T[]
): Promise<
  (T & {
    lastSyncSuccessAt: string | null
    lastSyncStatus: string
    autoSyncEnabled: boolean
    lastAutoSyncAt: string | null
  })[]
> {
  const views = await loadBrokerAccountSyncViews(
    supabase,
    accounts.map((a) => a.id)
  )
  return accounts.map((account) => {
    const sync = views.get(account.id)
    return {
      ...account,
      lastSyncSuccessAt: sync?.lastSyncSuccessAt ?? null,
      lastSyncStatus: sync?.lastSyncStatus ?? "never",
      autoSyncEnabled: sync?.autoSyncEnabled ?? true,
      lastAutoSyncAt: sync?.lastAutoSyncAt ?? null,
    }
  })
}
