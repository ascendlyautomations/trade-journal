import type { SupabaseClient } from "@supabase/supabase-js"
import type { RithmicServerConfig } from "@/lib/integrations/rithmic/rithmicEnv"
import {
  buildRithmicSessionConfigWithTransientPassword,
  loadRithmicConnectionIdentity,
  loadRithmicPhase1EnvSessionConfig,
} from "@/lib/integrations/rithmic/loadRithmicConnectionIdentity"

/**
 * @deprecated Rithmic passwords are transient. Use identity + transient password or Phase 1 env fallback.
 */
export async function loadRithmicSessionConfigForConnection(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
  }
): Promise<RithmicServerConfig | null> {
  return loadRithmicPhase1EnvSessionConfig(supabase, params)
}

export async function resolveRithmicSessionConfigForOperation(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
    transientPassword?: string | null
  }
): Promise<
  | { ok: true; config: RithmicServerConfig }
  | { ok: false; code: "rithmic_password_required"; userMessage: string }
> {
  const trimmedPassword =
    typeof params.transientPassword === "string"
      ? params.transientPassword
      : ""

  if (trimmedPassword) {
    const identity = await loadRithmicConnectionIdentity(supabase, {
      userId: params.userId,
      connectionId: params.connectionId,
    })
    if (!identity) {
      return {
        ok: false,
        code: "rithmic_password_required",
        userMessage: "Rithmic connection is not available. Connect again in Settings.",
      }
    }
    return {
      ok: true,
      config: buildRithmicSessionConfigWithTransientPassword(
        identity,
        trimmedPassword
      ),
    }
  }

  const legacyEnv = await loadRithmicPhase1EnvSessionConfig(supabase, {
    userId: params.userId,
    connectionId: params.connectionId,
  })
  if (legacyEnv) {
    return { ok: true, config: legacyEnv }
  }

  return {
    ok: false,
    code: "rithmic_password_required",
    userMessage:
      "Enter your Rithmic password to continue. TradeTraxs does not save your Rithmic password.",
  }
}
