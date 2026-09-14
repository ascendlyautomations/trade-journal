import type { SupabaseClient } from "@supabase/supabase-js"
import type { BrokerIntegrationProvider } from "@/lib/integrations/brokerIntegrationConnection"

export type OwnedBrokerConnection = {
  id: string
  user_id: string
  provider: string
  status: string
  provider_user_id: string | null
  provider_display_name: string | null
  connection_label: string | null
  api_environment: string | null
  connected_at: string | null
  last_sync_at: string | null
}

export async function loadOwnedBrokerConnection(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
    provider?: BrokerIntegrationProvider
  }
): Promise<OwnedBrokerConnection | null> {
  let query = supabase
    .from("broker_integration_connections")
    .select(
      "id, user_id, provider, status, provider_user_id, provider_display_name, connection_label, api_environment, connected_at, last_sync_at"
    )
    .eq("id", params.connectionId)
    .eq("user_id", params.userId)

  if (params.provider) {
    query = query.eq("provider", params.provider)
  }

  const { data, error } = await query.maybeSingle()
  if (error || !data) return null
  return data as OwnedBrokerConnection
}
