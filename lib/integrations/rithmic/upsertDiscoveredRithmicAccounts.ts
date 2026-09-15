import type { SupabaseClient } from "@supabase/supabase-js"
import {
  brokerAccountFieldsAfterRediscovery,
  findPriorBrokerAccountMappingForExternalId,
} from "@/lib/integrations/brokerIntegrationAccounts"
import {
  rithmicAccountSafeMetadata,
  type RithmicDiscoveredAccount,
} from "@/lib/integrations/rithmic/rithmicAccountModels"

export async function upsertDiscoveredRithmicAccounts(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
    discovered: RithmicDiscoveredAccount[]
  }
): Promise<void> {
  const now = new Date().toISOString()
  for (const account of params.discovered) {
    const { data: existing } = await supabase
      .from("broker_integration_accounts")
      .select("id, tradetraxs_account_id, status")
      .eq("connection_id", params.connectionId)
      .eq("provider", "rithmic")
      .eq("external_account_id", account.externalAccountId)
      .maybeSingle()

    const metadata = {
      ...rithmicAccountSafeMetadata({
        fcmId: account.fcmId,
        ibId: account.ibId,
        accountId: account.accountId,
        accountName: account.name,
        accountCurrency: account.accountCurrency,
        lossLimit: null,
        accountAutoLiquidate: null,
        autoLiqThresholdCurrentValue: null,
      }),
      ...account.metadata,
    }

    if (existing) {
      const continuity = brokerAccountFieldsAfterRediscovery(existing)
      const { error } = await supabase
        .from("broker_integration_accounts")
        .update({
          external_account_name: account.name,
          external_display_name: account.displayName,
          external_metadata: metadata,
          last_seen_at: now,
          updated_at: now,
          status: continuity.status,
          sync_enabled: continuity.syncEnabled,
        })
        .eq("id", existing.id)
      if (error) throw new Error("rithmic_broker_accounts_update_failed")
      continue
    }

    const prior = await findPriorBrokerAccountMappingForExternalId(supabase, {
      userId: params.userId,
      provider: "rithmic",
      externalAccountId: account.externalAccountId,
      excludeConnectionId: params.connectionId,
    })
    const inheritedTradetraxsId = prior?.tradetraxs_account_id ?? null

    const { error } = await supabase.from("broker_integration_accounts").insert({
      user_id: params.userId,
      connection_id: params.connectionId,
      provider: "rithmic",
      external_account_id: account.externalAccountId,
      external_account_name: account.name,
      external_display_name: account.displayName,
      external_metadata: metadata,
      tradetraxs_account_id: inheritedTradetraxsId,
      sync_enabled: Boolean(inheritedTradetraxsId),
      last_seen_at: now,
      updated_at: now,
      status: inheritedTradetraxsId ? "linked" : "discovered",
    })
    if (error) throw new Error("rithmic_broker_accounts_insert_failed")
  }
}
