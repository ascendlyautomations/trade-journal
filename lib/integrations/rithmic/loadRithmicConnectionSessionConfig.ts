import type { SupabaseClient } from "@supabase/supabase-js"
import {
  decryptIntegrationCredentials,
  isRithmicIntegrationCredentials,
} from "@/lib/integrations/credentialEncryption"
import { buildRithmicServerConfigFromUserCredentials } from "@/lib/integrations/rithmic/rithmicConnectionConfig"
import type { RithmicServerConfig } from "@/lib/integrations/rithmic/rithmicEnv"
import { loadRithmicServerConfigFromEnv } from "@/lib/integrations/rithmic/rithmicEnv"

/**
 * Session config for a broker connection: user-stored credentials when present,
 * otherwise server Test env (legacy Phase 1 saved connections without ciphertext).
 */
export async function loadRithmicSessionConfigForConnection(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
  }
): Promise<RithmicServerConfig | null> {
  const { data, error } = await supabase
    .from("broker_integration_connections")
    .select("status, credentials_ciphertext, api_environment")
    .eq("id", params.connectionId)
    .eq("user_id", params.userId)
    .eq("provider", "rithmic")
    .maybeSingle()

  if (error || !data) return null
  if (data.status !== "connected") return null

  const ciphertext = data.credentials_ciphertext
  if (ciphertext && typeof ciphertext === "string") {
    const payload = decryptIntegrationCredentials(ciphertext)
    if (!isRithmicIntegrationCredentials(payload)) {
      throw new Error("rithmic_connection_credentials_invalid")
    }
    return buildRithmicServerConfigFromUserCredentials(payload)
  }

  if (data.api_environment === "test") {
    try {
      return loadRithmicServerConfigFromEnv()
    } catch {
      return null
    }
  }

  return null
}
