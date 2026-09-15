import type { SupabaseClient } from "@supabase/supabase-js"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadOwnedBrokerConnection } from "@/lib/integrations/brokerConnectionAccess"
import {
  linkBrokerIntegrationAccount,
  listSafeBrokerIntegrationAccounts,
} from "@/lib/integrations/brokerIntegrationAccounts"
import { parseBrokerLinkCreateAccountPayload } from "@/lib/integrations/brokerLinkCreateAccountPayload"
import { insertTradingAccount } from "@/lib/tradingAccounts"
import type { TradingAccountPropFirmRules } from "@/lib/tradingAccounts"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

const integrationDb = supabaseServiceRole as SupabaseClient

type RouteContext = { params: Promise<{ connectionId: string }> }

type LinkBody = {
  brokerIntegrationAccountId?: string
  action?: "link" | "create"
  tradetraxsAccountId?: string
  createAccount?: {
    name?: string
    size?: string
    accountNumber?: string
    category?: string
    mode?: string | null
    rules?: TradingAccountPropFirmRules | null
  }
}

export async function POST(req: Request, context: RouteContext) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { connectionId } = await context.params
  const owned = await loadOwnedBrokerConnection(integrationDb, {
    userId: user.id,
    connectionId,
    provider: "rithmic",
  })
  if (!owned) {
    return Response.json({ error: "Connection not found." }, { status: 404 })
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
      "id, user_id, provider, connection_id, external_account_id, external_account_name, external_metadata, tradetraxs_account_id"
    )
    .eq("id", brokerIntegrationAccountId)
    .eq("user_id", user.id)
    .eq("provider", "rithmic")
    .eq("connection_id", connectionId)
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
        provider: "rithmic",
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
    const existingLinkId = brokerRow.tradetraxs_account_id?.trim()
    if (existingLinkId) {
      const { data: existingAccount, error: existingError } = await integrationDb
        .from("accounts")
        .select("id")
        .eq("id", existingLinkId)
        .eq("user_id", user.id)
        .maybeSingle()

      if (!existingError && existingAccount) {
        const accounts = await listSafeBrokerIntegrationAccounts(integrationDb, {
          userId: user.id,
          provider: "rithmic",
          connectionId,
        })
        return Response.json({
          ok: true,
          connectionId,
          accounts,
          tradetraxsAccountId: existingLinkId,
          alreadyLinked: true,
        })
      }
    }

    const meta = (brokerRow.external_metadata ?? {}) as Record<string, unknown>
    const accountIdFromMeta =
      typeof meta.accountId === "string" ? meta.accountId.trim() : ""
    const fallbackName =
      brokerRow.external_account_name?.trim() ||
      `Rithmic ${accountIdFromMeta || brokerRow.external_account_id}`

    const parsed = parseBrokerLinkCreateAccountPayload(body.createAccount ?? {}, fallbackName)
    if (!parsed.ok) {
      return Response.json({ error: parsed.message }, { status: 400 })
    }

    const accountId =
      parsed.payload.id?.trim() ||
      accountIdFromMeta ||
      brokerRow.external_account_id.split("|").pop()?.trim() ||
      String(brokerRow.external_account_id)

    const { account, error: createError } = await insertTradingAccount(integrationDb, user.id, {
      ...parsed.payload,
      id: accountId,
    })

    if (createError || !account) {
      return Response.json(
        { error: createError?.message ?? "Could not create trading account." },
        { status: 400 }
      )
    }

    try {
      await linkBrokerIntegrationAccount(integrationDb, {
        userId: user.id,
        provider: "rithmic",
        brokerAccountRowId: brokerIntegrationAccountId,
        tradetraxsAccountId: account.id,
      })
    } catch {
      await integrationDb
        .from("accounts")
        .delete()
        .eq("id", account.id)
        .eq("user_id", user.id)
      return Response.json({ error: "Account created but linking failed." }, { status: 500 })
    }
  }

  const now = new Date().toISOString()
  await integrationDb.from("broker_integration_account_sync").upsert(
    {
      broker_integration_account_id: brokerIntegrationAccountId,
      user_id: user.id,
      connection_id: connectionId,
      auto_sync_enabled: false,
      updated_at: now,
    },
    { onConflict: "broker_integration_account_id" }
  )

  const accounts = await listSafeBrokerIntegrationAccounts(integrationDb, {
    userId: user.id,
    provider: "rithmic",
    connectionId,
  })

  const linkedBrokerView = accounts.find((a) => a.id === brokerIntegrationAccountId)

  return Response.json({
    ok: true,
    connectionId,
    accounts,
    tradetraxsAccountId:
      linkedBrokerView?.tradetraxsAccountId ?? body.tradetraxsAccountId?.trim() ?? null,
  })
}
