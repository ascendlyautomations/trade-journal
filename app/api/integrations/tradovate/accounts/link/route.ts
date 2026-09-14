import type { SupabaseClient } from "@supabase/supabase-js"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

const integrationDb = supabaseServiceRole as SupabaseClient
import {
  linkBrokerIntegrationAccount,
  listSafeBrokerIntegrationAccounts,
} from "@/lib/integrations/brokerIntegrationAccounts"
import { assertRequiredAccountValue } from "@/lib/createAccountForm"
import { insertTradingAccount } from "@/lib/tradingAccounts"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

type LinkBody = {
  brokerIntegrationAccountId?: string
  action?: "link" | "create"
  tradetraxsAccountId?: string
  accountSize?: string
  accountName?: string
}

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: LinkBody
  try {
    body = (await req.json()) as LinkBody
  } catch {
    return Response.json({ error: "Invalid request." }, { status: 400 })
  }

  const brokerIntegrationAccountId = body.brokerIntegrationAccountId?.trim()
  const action = body.action
  if (!brokerIntegrationAccountId || (action !== "link" && action !== "create")) {
    return Response.json({ error: "Invalid request." }, { status: 400 })
  }

  const { data: brokerRow, error: brokerError } = await integrationDb
    .from("broker_integration_accounts")
    .select(
      "id, user_id, provider, external_account_id, external_account_name, external_metadata"
    )
    .eq("id", brokerIntegrationAccountId)
    .eq("user_id", user.id)
    .eq("provider", "tradovate")
    .maybeSingle()

  if (brokerError || !brokerRow) {
    return Response.json({ error: "Broker account not found." }, { status: 404 })
  }

  if (action === "link") {
    const tradetraxsAccountId = body.tradetraxsAccountId?.trim()
    if (!tradetraxsAccountId) {
      return Response.json({ error: "Select a TradeTraxs account." }, { status: 400 })
    }

    try {
      await linkBrokerIntegrationAccount(integrationDb, {
        userId: user.id,
        provider: "tradovate",
        brokerAccountRowId: brokerIntegrationAccountId,
        tradetraxsAccountId,
      })
    } catch (err) {
      const message = err instanceof Error ? err.message : "link_failed"
      if (message === "tradetraxs_account_not_owned") {
        return Response.json({ error: "That trading account is not available." }, { status: 403 })
      }
      return Response.json({ error: "Could not link account." }, { status: 500 })
    }
  } else {
    const metadata = (brokerRow.external_metadata ?? {}) as Record<string, unknown>
    const evaluationSize =
      typeof metadata.evaluationSize === "number" ? metadata.evaluationSize : null
    const sizeCandidate =
      body.accountSize?.trim() ||
      (evaluationSize != null ? String(Math.round(evaluationSize)) : "")
    const sizeGate = assertRequiredAccountValue(sizeCandidate)
    if (!sizeGate.ok) {
      return Response.json({ error: sizeGate.message }, { status: 400 })
    }

    const name =
      body.accountName?.trim() ||
      brokerRow.external_account_name?.trim() ||
      `Tradovate ${brokerRow.external_account_id}`

    const { account, error: createError } = await insertTradingAccount(
      integrationDb,
      user.id,
      {
        name,
        size: sizeGate.value,
        id: String(brokerRow.external_account_id),
        category: "Broker",
        mode: "Live",
        rules: null,
      }
    )

    if (createError || !account) {
      return Response.json(
        { error: createError?.message ?? "Could not create trading account." },
        { status: 400 }
      )
    }

    try {
      await linkBrokerIntegrationAccount(integrationDb, {
        userId: user.id,
        provider: "tradovate",
        brokerAccountRowId: brokerIntegrationAccountId,
        tradetraxsAccountId: account.id,
      })
    } catch {
      return Response.json({ error: "Account created but linking failed." }, { status: 500 })
    }
  }

  const accounts = await listSafeBrokerIntegrationAccounts(integrationDb, {
    userId: user.id,
    provider: "tradovate",
  })

  return Response.json({ ok: true, accounts })
}
