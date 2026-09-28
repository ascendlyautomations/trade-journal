import type { SupabaseClient } from "@supabase/supabase-js"
import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  runTradovateReportingProbe,
  runTradovateSyncRequestProbe,
  TRADOVATE_REFERENCE_SEP2026_FILL_IDS,
} from "@/lib/integrations/tradovate/tradovateHistoricalCapabilityProbe"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"
export const maxDuration = 120

const integrationDb = supabaseServiceRole as SupabaseClient

type ProbeBody = {
  connectionId?: string
  providerUserId?: number
  accountId?: string
  startDate?: string
  endDate?: string
}

function isServiceRoleRequest(req: Request): boolean {
  const expected = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim()
  if (!expected) return false
  const auth = req.headers.get("authorization")?.trim()
  if (!auth?.startsWith("Bearer ")) return false
  return auth.slice("Bearer ".length) === expected
}

/**
 * READ-ONLY Tradovate historical capability probes (syncrequest + Reporting API).
 * Enabled only when TRADOVATE_HISTORICAL_PROBE=1. Requires service-role bearer.
 */
export async function POST(req: Request) {
  if (process.env.TRADOVATE_HISTORICAL_PROBE !== "1") {
    return new Response(null, { status: 404 })
  }
  if (!isServiceRoleRequest(req)) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: ProbeBody = {}
  try {
    body = (await req.json()) as ProbeBody
  } catch {
    body = {}
  }

  const connectionId =
    body.connectionId?.trim() ?? "6ff59f30-9d9e-494e-bfec-3f022205088b"
  const accountId = body.accountId?.trim() ?? "65788591"
  const startDate = body.startDate?.trim() ?? "09/14/2026"
  const endDate = body.endDate?.trim() ?? "09/23/2026"

  const { data: conn, error: connErr } = await integrationDb
    .from("broker_integration_connections")
    .select("id, user_id, provider_user_id, api_environment, status")
    .eq("id", connectionId)
    .maybeSingle()

  if (connErr || !conn) {
    return Response.json(
      { ok: false, error: "connection_not_found", connectionId },
      { status: 404 }
    )
  }

  const userId = String(conn.user_id)
  const providerUserId =
    body.providerUserId ??
    (conn.provider_user_id != null ? Number(conn.provider_user_id) : NaN)

  if (!Number.isFinite(providerUserId)) {
    return Response.json({ ok: false, error: "provider_user_id_missing" }, { status: 400 })
  }

  const syncProbe = await runTradovateSyncRequestProbe(integrationDb, {
    userId,
    connectionId,
    providerUserId,
    accountId,
  })

  const reportingProbe = await runTradovateReportingProbe(integrationDb, {
    userId,
    connectionId,
    accountId,
    startDate,
    endDate,
    reportAccountEntityId: syncProbe.reportAccountEntityIdUsed,
    syncAccounts: syncProbe.accountsFromSync,
  })

  const matchedSyncAccount = syncProbe.accountsFromSync.find((a) => a.matchesRequestedAccountId)

  console.info(
    [
      "[TradovateHistoricalProbe] completed",
      `connectionId=${connectionId}`,
      `syncHttp=${syncProbe.httpStatus}`,
      `syncAccountId=${matchedSyncAccount?.id ?? "missing"}`,
      `syncAccountName=${matchedSyncAccount?.name ?? "missing"}`,
      `reportAccountEntityId=${reportingProbe.accountEncoding.reportAccountEntityId ?? "null"}`,
      `syncFillsAccount=${syncProbe.accountScoped.fills.count}`,
      `referencePresent=${syncProbe.referenceFillIdsPresentCount}/${syncProbe.referenceFillIdCount}`,
      `reportDefsHttp=${reportingProbe.definitions.httpStatus}`,
      `performanceError=${reportingProbe.performanceReport?.errorText ?? "none"}`,
      `performanceRows=${reportingProbe.performanceReport?.rowCount ?? 0}`,
      `performanceFillIds=${reportingProbe.performanceReport?.referenceFillIdsFoundCount ?? 0}`,
      `fillsError=${reportingProbe.fillsReport?.errorText ?? "none"}`,
      `fillsRows=${reportingProbe.fillsReport?.rowCount ?? 0}`,
      `fillsFillIds=${reportingProbe.fillsReport?.referenceFillIdsFoundCount ?? 0}`,
    ].join(" ")
  )

  return Response.json({
    ok: true,
    connectionId,
    userId,
    accountId,
    providerUserId,
    apiEnvironment: conn.api_environment,
    referenceFillIdCount: TRADOVATE_REFERENCE_SEP2026_FILL_IDS.length,
    syncProbe,
    reportingProbe,
  })
}
