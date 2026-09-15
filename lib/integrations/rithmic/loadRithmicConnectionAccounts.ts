import type { SupabaseClient } from "@supabase/supabase-js"
import { listSafeBrokerIntegrationAccounts } from "@/lib/integrations/brokerIntegrationAccounts"
import { attachSyncViewsToBrokerAccounts } from "@/lib/integrations/tradovate/runTradovateAccountTradeSync"

export async function loadRithmicConnectionAccounts(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string
): Promise<{
  connectionStatus: string
  accounts: Awaited<ReturnType<typeof attachSyncViewsToBrokerAccounts>>
}> {
  const { data: connection } = await supabase
    .from("broker_integration_connections")
    .select("status")
    .eq("id", connectionId)
    .eq("user_id", userId)
    .eq("provider", "rithmic")
    .maybeSingle()

  const accounts = await listSafeBrokerIntegrationAccounts(supabase, {
    userId,
    provider: "rithmic",
    connectionId,
  })
  const accountsWithSync = await attachSyncViewsToBrokerAccounts(supabase, accounts)

  return {
    connectionStatus: connection?.status ?? "not_connected",
    accounts: accountsWithSync,
  }
}
