import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  isRithmicPhase1ApiEnabled,
  rithmicEnvPresenceDiagnostic,
} from "@/lib/integrations/rithmic/rithmicEnv"
import {
  rithmicPhase1ErrorMessage,
  type RithmicPhase1ApiErrorCode,
} from "@/lib/integrations/rithmic/rithmicPhase1ApiErrors"
import {
  defaultRithmicSslCaPath,
  verifyRithmicRuntimeAssets,
} from "@/lib/integrations/rithmic/rithmicPaths"
import { runRithmicPhase1Discovery } from "@/lib/integrations/rithmic/runRithmicPhase1Discovery"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"
/** Allow system-info + login + account list on Vercel (Pro). */
export const maxDuration = 60

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

  if (!envPresence.apiEnvIsTest) {
    return jsonError("rithmic_env_invalid", 503, { envPresence })
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
    console.error("[rithmic/phase1/discovery] unhandled", message)

    if (message === "rithmic_api_credentials_missing") {
      return jsonError("rithmic_env_missing", 503, { envPresence: rithmicEnvPresenceDiagnostic() })
    }
    if (message === "rithmic_api_env_must_be_test" || message === "rithmic_wss_url_must_use_wss") {
      return jsonError("rithmic_env_invalid", 503)
    }

    const runtimeAssets = verifyRithmicRuntimeAssets(defaultRithmicSslCaPath())
    if (
      message.includes("ENOENT") ||
      message.includes("rithmic_proto") ||
      message.includes("no such file")
    ) {
      return Response.json({
        ok: false,
        userMessage:
          "Rithmic protocol files are missing on the server. Redeploy with third_party Rithmic assets included.",
        code: "runtime_assets_missing",
        runtimeAssets,
        envPresence: rithmicEnvPresenceDiagnostic(),
        lastSuccessfulStage: "env_preflight",
        failureStage: "runtime_assets_verified",
        diagnostics: [message.slice(0, 120)],
      })
    }

    if (
      message.includes("ECONNREFUSED") ||
      message.includes("ENOTFOUND") ||
      message.includes("WebSocket")
    ) {
      return jsonError("rithmic_wss_connect_failed", 502, {
        detail: message.slice(0, 120),
        runtimeAssets,
      })
    }

    return jsonError("rithmic_discovery_failed", 500, {
      detail: message.slice(0, 120),
      runtimeAssets,
    })
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
    runtimeAssets: verifyRithmicRuntimeAssets(defaultRithmicSslCaPath()),
  })
}
