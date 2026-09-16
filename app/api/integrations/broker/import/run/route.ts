import type { SupabaseClient } from "@supabase/supabase-js"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  listLinkedBrokerImportTargets,
  runBrokerManualImportBatch,
} from "@/lib/brokerImport/brokerManualImport"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"
export const maxDuration = 120

const integrationDb = supabaseServiceRole as SupabaseClient

type Body = {
  mappingIds?: string[]
  /** Transient Rithmic password for manual import (never stored). */
  rithmicPassword?: string
}

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: Body = {}
  try {
    body = (await req.json()) as Body
  } catch {
    body = {}
  }

  const allTargets = await listLinkedBrokerImportTargets(integrationDb, user.id)
  if (allTargets.length === 0) {
    return Response.json({ error: "No linked broker accounts." }, { status: 400 })
  }

  const requested = new Set(
    (body.mappingIds ?? []).map((id) => id.trim()).filter(Boolean)
  )
  const targets =
    requested.size > 0
      ? allTargets.filter((t) => requested.has(t.mappingId))
      : allTargets

  if (targets.length === 0) {
    return Response.json({ error: "Invalid account selection." }, { status: 400 })
  }

  const rithmicPassword =
    typeof body.rithmicPassword === "string" && body.rithmicPassword
      ? body.rithmicPassword
      : null

  const batch = await runBrokerManualImportBatch(integrationDb, user.id, targets, {
    rithmicPassword,
  })

  return Response.json({
    ok: batch.ok,
    newTradeIds: batch.newTradeIds,
    totalTradesCreated: batch.totalTradesCreated,
    totalTradesUpdated: batch.totalTradesUpdated,
    results: batch.results,
  })
}
