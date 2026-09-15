import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isRithmicPhase1ApiEnabled } from "@/lib/integrations/rithmic/rithmicEnv"
import { runRithmicPhase1Discovery } from "@/lib/integrations/rithmic/runRithmicPhase1Discovery"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

/** Server-side Rithmic Test discovery (Phase 1). Uses RITHMIC_* env credentials only. */
export async function POST(req: Request) {
  if (!isRithmicPhase1ApiEnabled()) {
    return Response.json({ error: "Rithmic Phase 1 API is not enabled." }, { status: 403 })
  }

  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
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
    if (message === "rithmic_api_credentials_missing" || message === "rithmic_api_env_must_be_test") {
      return Response.json({ error: "Rithmic server configuration is incomplete." }, { status: 503 })
    }
    console.error("[rithmic/phase1/discovery]", message)
    return Response.json({ error: "Rithmic discovery failed." }, { status: 500 })
  }
}

export async function GET() {
  return Response.json({
    phase: 1,
    enabled: isRithmicPhase1ApiEnabled(),
    scope: "Rithmic Test only — vendor env credentials on server",
    productionReady: false,
  })
}
