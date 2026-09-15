import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  isRithmicPhase1ApiEnabled,
  rithmicEnvPresenceDiagnostic,
} from "@/lib/integrations/rithmic/rithmicEnv"
import {
  rithmicPhase1ErrorMessage,
  type RithmicPhase1ApiErrorCode,
} from "@/lib/integrations/rithmic/rithmicPhase1ApiErrors"
import { runRithmicPhase1Discovery } from "@/lib/integrations/rithmic/runRithmicPhase1Discovery"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

function jsonError(code: RithmicPhase1ApiErrorCode, status: number, extra?: Record<string, unknown>) {
  return Response.json(
    {
      code,
      error: rithmicPhase1ErrorMessage(code),
      ...extra,
    },
    { status }
  )
}

/** Server-side Rithmic Test discovery (Phase 1). Uses RITHMIC_* env credentials only. */
export async function POST(req: Request) {
  if (!isRithmicPhase1ApiEnabled()) {
    return jsonError("rithmic_phase1_disabled", 403)
  }

  const user = await getRouteUser(req)
  if (!user?.id) {
    return jsonError("tradetraxs_auth_required", 401)
  }

  const envPresence = rithmicEnvPresenceDiagnostic()
  if (!envPresence.apiUserSet || !envPresence.apiPasswordSet) {
    console.error("[rithmic/phase1/discovery] env_missing", JSON.stringify(envPresence))
    return jsonError("rithmic_env_missing", 503, { envPresence })
  }

  let persist = false
  try {
    const body = (await req.json().catch(() => ({}))) as { persist?: boolean }
    persist = body.persist === true
  } catch {
    persist = false
  }

  try {
    const result = await runRithmicPhase1Discovery({
      persistForUserId: persist ? user.id : null,
      supabase: persist ? supabaseServiceRole : null,
    })
    return Response.json(result)
  } catch (err) {
    const message = err instanceof Error ? err.message : "unknown"
    if (message === "rithmic_api_credentials_missing") {
      return jsonError("rithmic_env_missing", 503, { envPresence: rithmicEnvPresenceDiagnostic() })
    }
    if (message === "rithmic_api_env_must_be_test" || message === "rithmic_wss_url_must_use_wss") {
      return jsonError("rithmic_env_invalid", 503)
    }
    if (
      message.includes("ECONNREFUSED") ||
      message.includes("ENOTFOUND") ||
      message.includes("rithmic_socket") ||
      message.includes("WebSocket")
    ) {
      console.error("[rithmic/phase1/discovery] wss_failed", message)
      return jsonError("rithmic_wss_connect_failed", 502)
    }
    console.error("[rithmic/phase1/discovery]", message)
    return jsonError("rithmic_discovery_failed", 500)
  }
}

export async function GET(req: Request) {
  const enabled = isRithmicPhase1ApiEnabled()
  const base = {
    phase: 1,
    enabled,
    scope: "Rithmic Test only — vendor env credentials on server",
    productionReady: false,
  }

  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json(base)
  }

  return Response.json({
    ...base,
    envPresence: rithmicEnvPresenceDiagnostic(),
  })
}
