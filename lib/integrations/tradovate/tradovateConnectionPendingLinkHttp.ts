import type { SupabaseClient } from "@supabase/supabase-js"
import {
  clearBrokerConnectionPendingLink,
  setBrokerConnectionPendingLink,
} from "@/lib/integrations/brokerConnectionPendingLink"
import { parseBrokerLinkCreateAccountPayload } from "@/lib/integrations/brokerLinkCreateAccountPayload"
import { insertTradingAccount } from "@/lib/tradingAccounts"
import { proLimitResponseFromError } from "@/lib/server/proLimitFromError"

export type TradovatePendingLinkHttpBody = {
  action?: "link" | "create" | "clear"
  tradetraxsAccountId?: string
  createAccount?: {
    name?: string
    size?: string
    accountNumber?: string
    category?: string
    mode?: string | null
    rules?: Record<string, unknown> | null
    purchaseCost?: string | null
    purchaseDate?: string | null
  }
}

export type TradovatePendingLinkSuccessJson = {
  ok: true
  connectionId: string
  pendingLink: {
    tradetraxsAccountId: string
    tradetraxsAccountName: string | null
  }
}

export function parseTradovatePendingLinkHttpBody(
  raw: unknown
): TradovatePendingLinkHttpBody | null {
  if (!raw || typeof raw !== "object") return null
  return raw as TradovatePendingLinkHttpBody
}

export async function mutateTradovateConnectionPendingLink(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
    body: TradovatePendingLinkHttpBody
  }
): Promise<Response> {
  const { userId, connectionId, body } = params
  const action = body.action

  if (action === "clear") {
    try {
      await clearBrokerConnectionPendingLink(supabase, { userId, connectionId })
      return Response.json({ ok: true, connectionId, pendingLink: null })
    } catch (err) {
      console.error(
        "[tradovate/pending-link] clear_failed",
        err instanceof Error ? err.message : "unknown"
      )
      return Response.json({ error: "Could not clear pending link." }, { status: 500 })
    }
  }

  if (action !== "link" && action !== "create") {
    return Response.json({ error: "Invalid request." }, { status: 400 })
  }

  try {
    let tradetraxsAccountId: string

    if (action === "link") {
      const raw = body.tradetraxsAccountId?.trim()
      if (!raw) {
        return Response.json({ error: "Select a TradeTraxs account." }, { status: 400 })
      }
      tradetraxsAccountId = raw
    } else {
      const parsed = parseBrokerLinkCreateAccountPayload(
        body.createAccount ?? {},
        "Tradovate Account"
      )
      if (!parsed.ok) {
        return Response.json({ error: parsed.message }, { status: 400 })
      }
      try {
        const created = await insertTradingAccount(supabase, userId, parsed.payload)
        if (!created.account?.id) {
          return Response.json(
            { error: created.error?.message ?? "Could not create trading account." },
            { status: 400 }
          )
        }
        tradetraxsAccountId = created.account.id
      } catch (err) {
        const pro = proLimitResponseFromError(err)
        if (pro) return pro
        throw err
      }
    }

    const pendingLink = await setBrokerConnectionPendingLink(supabase, {
      userId,
      connectionId,
      tradetraxsAccountId,
    })

    const payload: TradovatePendingLinkSuccessJson = {
      ok: true,
      connectionId,
      pendingLink,
    }
    return Response.json(payload)
  } catch (err) {
    const message = err instanceof Error ? err.message : "unknown"
    if (message === "broker_accounts_already_discovered") {
      return Response.json(
        {
          error:
            "Broker trading accounts are available now. Link them directly instead of saving a pending preference.",
        },
        { status: 409 }
      )
    }
    if (message === "tradetraxs_account_not_owned") {
      return Response.json({ error: "That trading account is not available." }, { status: 403 })
    }
    if (message === "broker_connection_not_connected") {
      return Response.json({ error: "Connect Tradovate first." }, { status: 400 })
    }
    if (message === "broker_pending_link_set_failed") {
      return Response.json(
        {
          error:
            "Could not save pending link. If this persists, confirm broker connection schema migrations are applied.",
        },
        { status: 500 }
      )
    }
    console.error("[tradovate/pending-link] set_failed", message)
    return Response.json({ error: "Could not save pending link." }, { status: 500 })
  }
}