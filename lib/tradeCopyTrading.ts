import type { SupabaseClient } from "@supabase/supabase-js"
import { ensureManualUserAccountRegistered } from "./ensureManualUserAccount"
import { prependTradeInCache } from "./appDataCache"
import type { TradingAccountListItem } from "./tradingAccounts"

export function isCopyTradedTrade(
  trade: { copy_trading_group_id?: string | null } | null | undefined
): boolean {
  return trade?.copy_trading_group_id != null && String(trade.copy_trading_group_id).trim() !== ""
}

export type ManualTradeAccountSnapshot = {
  type: string
  name: string | null
  size: string | null
  id: string | null
  account_number: string | null
  mode: string
  category: string | null
}

export function accountToTradeSnapshot(
  account: TradingAccountListItem
): ManualTradeAccountSnapshot {
  const modeLower = String(account.mode ?? "live").trim().toLowerCase()
  return {
    type: modeLower,
    name: String(account.name ?? "").trim() || null,
    size: String(account.size ?? "").trim() || null,
    id: account.id != null ? String(account.id).trim() || null : null,
    account_number: String(account.account_number ?? "").trim() || null,
    mode: String(account.mode ?? "live"),
    category: account.category ?? null,
  }
}

type InsertCopyTradedTradesParams = {
  client: SupabaseClient
  userId: string
  isPro: boolean
  groupId: string
  accounts: TradingAccountListItem[]
  tradeTemplate: Record<string, unknown>
  isPublic: boolean
  postCaption?: string | null
}

export async function insertCopyTradedTrades({
  client,
  userId,
  isPro,
  groupId,
  accounts,
  tradeTemplate,
  isPublic,
  postCaption = null,
}: InsertCopyTradedTradesParams): Promise<
  | { ok: true; trades: Record<string, unknown>[] }
  | { ok: false; message: string }
> {
  if (accounts.length === 0) {
    return { ok: false, message: "Copy trading group has no linked accounts." }
  }

  for (const account of accounts) {
    const snapshot = accountToTradeSnapshot(account)
    const skipRegistry =
      snapshot.type === "backtest" || snapshot.type === "imported"
    const ensured = await ensureManualUserAccountRegistered(client, {
      userId,
      accountName: snapshot.name ?? "",
      tradeAccountType: snapshot.type,
      isPro,
      skipRegistry,
    })
    if (!ensured.ok) {
      return {
        ok: false,
        message:
          ensured.reason === "limit"
            ? "Free plan account limit reached."
            : "Could not complete save. Please try again.",
      }
    }
  }

  const rows = accounts.map((account) => {
    const snapshot = accountToTradeSnapshot(account)
    return {
      ...tradeTemplate,
      account_name: snapshot.name,
      account_size: snapshot.size,
      account_id: snapshot.id,
      mode: snapshot.mode,
      account_category: snapshot.category,
      account_type: snapshot.type,
      copy_trading_group_id: groupId,
    }
  })

  const { data: insertedTrades, error } = await client
    .from("trades")
    .insert(rows)
    .select()

  if (error) {
    console.error("[insertCopyTradedTrades] insert error:", error)
    return { ok: false, message: error.message || "Could not save trades." }
  }

  const trades = (insertedTrades ?? []) as Record<string, unknown>[]
  for (const trade of trades) {
    prependTradeInCache(userId, trade)
  }

  if (isPublic && trades.length > 0) {
    const postRows = trades.map((trade) => ({
      user_id: userId,
      trade_id: trade.id,
      image_url: tradeTemplate.image_url ?? null,
      pnl: tradeTemplate.pnl ?? null,
      rr: tradeTemplate.rr ?? null,
      caption: postCaption ?? "",
    }))
    const { error: postError } = await client.from("posts").insert(postRows)
    if (postError) {
      console.error("[insertCopyTradedTrades] post insert error:", postError)
      return { ok: false, message: postError.message || "Could not publish trades." }
    }
  }

  return { ok: true, trades }
}
