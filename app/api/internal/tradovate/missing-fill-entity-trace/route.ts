import type { SupabaseClient } from "@supabase/supabase-js"
import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  formatTradovateMissingFillEntityTraceMatrix,
  resolveConnectedTradovateMapping,
  runTradovateMissingFillEntityTrace,
} from "@/lib/integrations/tradovate/tradovateMissingFillEntityTrace"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"
export const maxDuration = 120

const integrationDb = supabaseServiceRole as SupabaseClient

type TraceBody = {
  externalAccountId?: string
  fillIds?: string[]
}

function isServiceRoleRequest(req: Request): boolean {
  const expected = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim()
  if (!expected) return false
  const auth = req.headers.get("authorization")?.trim()
  if (!auth?.startsWith("Bearer ")) return false
  return auth.slice("Bearer ".length) === expected
}

/**
 * READ-ONLY Tradovate entity trace (production credentials on server).
 * Enabled only when TRADOVATE_ENTITY_TRACE=1. Requires service-role bearer.
 * Does not log raw Tradovate payloads.
 */
export async function POST(req: Request) {
  if (process.env.TRADOVATE_ENTITY_TRACE !== "1") {
    return new Response(null, { status: 404 })
  }
  if (!isServiceRoleRequest(req)) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: TraceBody = {}
  try {
    body = (await req.json()) as TraceBody
  } catch {
    body = {}
  }

  const externalAccountId = body.externalAccountId?.trim() || "65788591"

  try {
    const mapping = await resolveConnectedTradovateMapping(
      integrationDb,
      externalAccountId
    )
    const { data: connectionRow } = await integrationDb
      .from("broker_integration_connections")
      .select("api_environment, provider_user_id")
      .eq("id", mapping.connectionId)
      .maybeSingle()
    const result = await runTradovateMissingFillEntityTrace(integrationDb, {
      ...mapping,
      apiEnvironment: connectionRow?.api_environment ?? null,
      providerUserId:
        connectionRow?.provider_user_id != null
          ? String(connectionRow.provider_user_id)
          : null,
      fillIds: body.fillIds,
    })

    console.info(
      "[TradovateEntityTrace] completed",
      `accountId=${result.accountId}`,
      `fillListTotal=${result.fillListTotalCount}`,
      `orderDepsCount=${result.orderDepsAccountOrderCount}`
    )

    return Response.json({
      ok: true,
      matrixText: formatTradovateMissingFillEntityTraceMatrix(result),
      result,
    })
  } catch (err) {
    const message = err instanceof Error ? err.message : "trace_failed"
    console.error("[TradovateEntityTrace] failed", message.slice(0, 200))
    return Response.json({ ok: false, error: message }, { status: 500 })
  }
}
