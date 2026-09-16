import type { SupabaseClient } from "@supabase/supabase-js"
import type { RithmicApiEnvironment } from "@/lib/integrations/rithmic/rithmicEnv"
import { loadRithmicServerConfigFromEnv } from "@/lib/integrations/rithmic/rithmicEnv"
import type { RithmicServerConfig } from "@/lib/integrations/rithmic/rithmicEnv"
import { buildRithmicServerConfigForVerification } from "@/lib/integrations/rithmic/rithmicConnectionConfig"

export type RithmicConnectionIdentity = {
  username: string
  systemName: string
  apiEnvironment: RithmicApiEnvironment
}

/**
 * Non-secret Rithmic connection fields used with a transient password per operation.
 */
export async function loadRithmicConnectionIdentity(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
  }
): Promise<RithmicConnectionIdentity | null> {
  const { data, error } = await supabase
    .from("broker_integration_connections")
    .select(
      "status, broker_login_username, provider_display_name, api_environment, credentials_ciphertext"
    )
    .eq("id", params.connectionId)
    .eq("user_id", params.userId)
    .eq("provider", "rithmic")
    .maybeSingle()

  if (error || !data) return null
  if (data.status !== "connected" && data.status !== "reconnect_required") {
    return null
  }

  const username =
    typeof data.broker_login_username === "string"
      ? data.broker_login_username.trim()
      : ""
  const systemName =
    typeof data.provider_display_name === "string"
      ? data.provider_display_name.trim()
      : ""

  if (!username || !systemName) {
    return null
  }

  const apiEnvironment =
    data.api_environment === "test" ||
    data.api_environment === "demo" ||
    data.api_environment === "live"
      ? (data.api_environment as RithmicApiEnvironment)
      : ("test" as const)

  return { username, systemName, apiEnvironment }
}

/** Legacy Phase 1 test connections without stored username — server Test env only. */
export async function loadRithmicPhase1EnvSessionConfig(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
  }
): Promise<RithmicServerConfig | null> {
  const { data, error } = await supabase
    .from("broker_integration_connections")
    .select("status, broker_login_username, api_environment, credentials_ciphertext")
    .eq("id", params.connectionId)
    .eq("user_id", params.userId)
    .eq("provider", "rithmic")
    .maybeSingle()

  if (error || !data) return null
  if (data.status !== "connected") return null
  if (data.credentials_ciphertext) return null
  if (data.broker_login_username?.trim()) return null
  if (data.api_environment !== "test") return null

  try {
    return loadRithmicServerConfigFromEnv()
  } catch {
    return null
  }
}

export function buildRithmicSessionConfigWithTransientPassword(
  identity: RithmicConnectionIdentity,
  password: string
): RithmicServerConfig {
  return buildRithmicServerConfigForVerification({
    username: identity.username,
    password,
    systemName: identity.systemName,
  })
}
