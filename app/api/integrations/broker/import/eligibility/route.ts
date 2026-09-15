import type { SupabaseClient } from "@supabase/supabase-js"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { listLinkedBrokerImportTargets } from "@/lib/brokerImport/brokerManualImport"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

const integrationDb = supabaseServiceRole as SupabaseClient

export async function GET(req: Request) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { data: profile } = await integrationDb
    .from("profiles")
    .select("tradovate_login_import_reminder_opt_out, onboarding_completed")
    .eq("id", user.id)
    .maybeSingle()

  const targets = await listLinkedBrokerImportTargets(integrationDb, user.id)

  return Response.json({
    eligible:
      profile?.onboarding_completed === true &&
      profile?.tradovate_login_import_reminder_opt_out !== true &&
      targets.length > 0,
    optOut: profile?.tradovate_login_import_reminder_opt_out === true,
    linkedAccounts: targets.map((t) => ({
      provider: t.provider,
      mappingId: t.mappingId,
      connectionId: t.connectionId,
      brokerAccountLabel: t.brokerAccountLabel,
      tradetraxsAccountName: t.tradetraxsAccountName,
    })),
  })
}
