import type { SupabaseClient } from "@supabase/supabase-js"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { listLinkedBrokerImportTargets } from "@/lib/brokerImport/brokerManualImport"
import {
  listLinkedBrokerAccountMappingsForUser,
} from "@/lib/integrations/brokerIntegrationAccounts"
import { listSafeBrokerConnections } from "@/lib/integrations/brokerIntegrationConnection"

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

  const [importTargets, linkedMappings, tradovateConnections, rithmicConnections] =
    await Promise.all([
      listLinkedBrokerImportTargets(integrationDb, user.id),
      listLinkedBrokerAccountMappingsForUser(integrationDb, user.id),
      listSafeBrokerConnections(integrationDb, {
        userId: user.id,
        provider: "tradovate",
      }),
      listSafeBrokerConnections(integrationDb, {
        userId: user.id,
        provider: "rithmic",
      }),
    ])

  const connectionCount = tradovateConnections.length + rithmicConnections.length
  const hasSupportedConnection =
    tradovateConnections.some((c) => c.connected) ||
    rithmicConnections.some((c) => c.connected)
  const hasLinkedAccount = importTargets.length > 0
  const canImportImmediately = hasLinkedAccount
  const needsAccountLinking = hasSupportedConnection && !hasLinkedAccount
  const onboardingComplete = profile?.onboarding_completed === true
  const optOut = profile?.tradovate_login_import_reminder_opt_out === true

  return Response.json({
    /** @deprecated Prefer `canImportImmediately` — legacy login-import reminder gate. */
    eligible:
      onboardingComplete && !optOut && canImportImmediately,
    optOut,
    connectionCount,
    linkedAccountCount: linkedMappings.length,
    hasSupportedConnection,
    hasLinkedAccount,
    canImportImmediately,
    needsAccountLinking,
    connectedProviders: {
      tradovate: tradovateConnections.some((c) => c.connected),
      rithmic: rithmicConnections.some((c) => c.connected),
    },
    linkedAccounts: linkedMappings.map((t) => ({
      provider: t.provider,
      mappingId: t.mappingId,
      connectionId: t.connectionId,
      brokerAccountLabel: t.brokerAccountLabel,
      tradetraxsAccountName: t.tradetraxsAccountName,
    })),
  })
}
