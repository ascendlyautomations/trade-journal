import type { SupabaseClient } from "@supabase/supabase-js"
import {
  encryptIntegrationCredentials,
  type RithmicIntegrationCredentials,
} from "@/lib/integrations/credentialEncryption"
import { maskBrokerIdentifier } from "@/lib/integrations/rithmic/rithmicSyncLogger"
import { upsertDiscoveredRithmicAccounts } from "@/lib/integrations/rithmic/upsertDiscoveredRithmicAccounts"
import type { RithmicDiscoveredAccount } from "@/lib/integrations/rithmic/rithmicAccountModels"
import type { RithmicApiEnvironment } from "@/lib/integrations/rithmic/rithmicEnv"

const ACTIVE_STATUSES = ["connected", "reconnect_required", "error"] as const

export async function persistVerifiedRithmicUserConnection(
  supabase: SupabaseClient,
  params: {
    userId: string
    username: string
    password: string
    systemName: string
    apiEnvironment: RithmicApiEnvironment
    uniqueUserId: string | null
    discoveredAccounts: RithmicDiscoveredAccount[]
    reconnectConnectionId?: string | null
  }
): Promise<{ connectionId: string }> {
  const now = new Date().toISOString()
  const credentials: RithmicIntegrationCredentials = {
    kind: "rithmic",
    username: params.username.trim(),
    password: params.password,
    systemName: params.systemName.trim(),
    apiEnvironment: "test",
  }
  const ciphertext = encryptIntegrationCredentials(credentials)

  const maskedLogin = maskBrokerIdentifier(params.username.trim())
  const providerUserId =
    params.uniqueUserId?.trim() ||
    `rithmic:${params.username.trim().toLowerCase()}`
  const displayName = params.systemName.trim()
  const connectionLabel = `Rithmic ${params.apiEnvironment} · ${maskedLogin}`

  const baseRow = {
    status: "connected" as const,
    provider_user_id: providerUserId,
    provider_display_name: displayName,
    connection_label: connectionLabel,
    api_environment: params.apiEnvironment,
    credentials_ciphertext: ciphertext,
    access_token_expires_at: null,
    refresh_token_expires_at: null,
    connected_at: now,
    disconnected_at: null,
    last_verified_at: now,
    updated_at: now,
  }

  let connectionId: string

  if (params.reconnectConnectionId) {
    const { data: target, error: targetError } = await supabase
      .from("broker_integration_connections")
      .select("id, provider_user_id")
      .eq("id", params.reconnectConnectionId)
      .eq("user_id", params.userId)
      .eq("provider", "rithmic")
      .maybeSingle()

    if (targetError || !target) {
      throw new Error("rithmic_reconnect_target_not_found")
    }

    if (
      target.provider_user_id &&
      target.provider_user_id !== providerUserId &&
      params.uniqueUserId
    ) {
      throw new Error("rithmic_reconnect_identity_mismatch")
    }

    const { error } = await supabase
      .from("broker_integration_connections")
      .update({
        ...baseRow,
        provider_user_id: providerUserId,
      })
      .eq("id", target.id)

    if (error) throw new Error("rithmic_connection_update_failed")
    connectionId = target.id
  } else {
    const { data: existing } = await supabase
      .from("broker_integration_connections")
      .select("id")
      .eq("user_id", params.userId)
      .eq("provider", "rithmic")
      .eq("provider_user_id", providerUserId)
      .in("status", [...ACTIVE_STATUSES])
      .maybeSingle()

    if (existing?.id) {
      const { error } = await supabase
        .from("broker_integration_connections")
        .update(baseRow)
        .eq("id", existing.id)
      if (error) throw new Error("rithmic_connection_update_failed")
      connectionId = existing.id
    } else {
      const { data: inserted, error: insertError } = await supabase
        .from("broker_integration_connections")
        .insert({
          user_id: params.userId,
          provider: "rithmic",
          ...baseRow,
        })
        .select("id")
        .single()

      if (insertError || !inserted) throw new Error("rithmic_connection_insert_failed")
      connectionId = inserted.id
    }
  }

  await upsertDiscoveredRithmicAccounts(supabase, {
    userId: params.userId,
    connectionId,
    discovered: params.discoveredAccounts,
  })

  return { connectionId }
}
