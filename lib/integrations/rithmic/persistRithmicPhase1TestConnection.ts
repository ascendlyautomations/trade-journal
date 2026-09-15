import type { SupabaseClient } from "@supabase/supabase-js"

/**
 * Phase 1: persist a test-scoped connection row without storing vendor env passwords.
 * End-user credential storage is deferred until the connection model is confirmed.
 */
export async function persistRithmicPhase1TestConnection(
  supabase: SupabaseClient,
  params: {
    userId: string
    uniqueUserId: string
    systemName: string
  }
): Promise<{ connectionId: string }> {
  const now = new Date().toISOString()

  const { data: existing } = await supabase
    .from("broker_integration_connections")
    .select("id")
    .eq("user_id", params.userId)
    .eq("provider", "rithmic")
    .eq("provider_user_id", params.uniqueUserId)
    .in("status", ["connected", "reconnect_required", "error"])
    .maybeSingle()

  const row = {
    status: "connected" as const,
    provider_user_id: params.uniqueUserId,
    provider_display_name: params.systemName,
    connection_label: "Rithmic Test (Phase 1)",
    api_environment: "test",
    credentials_ciphertext: null,
    connected_at: now,
    disconnected_at: null,
    updated_at: now,
  }

  if (existing?.id) {
    const { error } = await supabase
      .from("broker_integration_connections")
      .update(row)
      .eq("id", existing.id)
    if (error) throw new Error("rithmic_connection_update_failed")
    return { connectionId: existing.id }
  }

  const { data: inserted, error: insertError } = await supabase
    .from("broker_integration_connections")
    .insert({
      user_id: params.userId,
      provider: "rithmic",
      ...row,
    })
    .select("id")
    .single()

  if (insertError || !inserted) throw new Error("rithmic_connection_insert_failed")
  return { connectionId: inserted.id }
}
