import type { SupabaseClient } from "@supabase/supabase-js"
import { ensureManualUserAccountRegistered } from "./ensureManualUserAccount"
import { prependTradeInCache } from "./appDataCache"
import { assertAccountAllowsNewTrades } from "./freePlanAccountSlots"
import type { TradingAccountListItem } from "./tradingAccounts"
import { isCopyTradedMode } from "./tradeMode"
import { toUserFacingErrorMessage, USER_FACING_ERROR_MESSAGES } from "./userFacingError"

export function isCopyTradedTrade(
  trade: {
    trade_mode?: unknown
    copied_account_ids?: unknown
    copy_trading_group_id?: string | null
  } | null | undefined
): boolean {
  return isCopyTradedMode(trade)
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
  /** Optional legacy copy-trading group link. */
  groupId?: string | null
  accounts: TradingAccountListItem[]
  tradeTemplate: Record<string, unknown>
  isPublic: boolean
  postCaption?: string | null
  sourceAccountId?: string | null
  copiedAccountIds?: readonly string[]
}

export async function insertCopyTradedTrades({
  client,
  userId,
  isPro,
  groupId = null,
  accounts,
  tradeTemplate,
  isPublic,
  postCaption = null,
  sourceAccountId = null,
  copiedAccountIds = [],
}: InsertCopyTradedTradesParams): Promise<
  | { ok: true; trades: Record<string, unknown>[] }
  | { ok: false; message: string }
> {
  if (accounts.length === 0) {
    return { ok: false, message: "Copy trading group has no linked accounts." }
  }

  const { data: profile } = await client
    .from("profiles")
    .select("is_pro, subscription_status, trial_end")
    .eq("id", userId)
    .maybeSingle()

  for (const account of accounts) {
    const entryGate = await assertAccountAllowsNewTrades(
      client,
      userId,
      account.id,
      profile
    )
    if (!entryGate.ok) {
      return { ok: false, message: entryGate.message }
    }

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

  const normalizedCopied = [
    ...new Set(
      (copiedAccountIds ?? [])
        .map((id) => String(id ?? "").trim())
        .filter(Boolean)
    ),
  ]
  const normalizedSource =
    sourceAccountId != null && String(sourceAccountId).trim() !== ""
      ? String(sourceAccountId).trim()
      : null

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
      trade_mode: "copy_traded",
      source_account_id: normalizedSource,
      copied_account_ids: normalizedCopied,
      ...(groupId ? { copy_trading_group_id: groupId } : {}),
    }
  })

  const { data: insertedTrades, error } = await client
    .from("trades")
    .insert(rows)
    .select()

  if (error) {
    console.error("[insertCopyTradedTrades] insert error:", error)
    return {
      ok: false,
      message: toUserFacingErrorMessage(
        error,
        USER_FACING_ERROR_MESSAGES.TRADE_SAVE_FAILED
      ),
    }
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
      return {
        ok: false,
        message: toUserFacingErrorMessage(
          postError,
          "Could not publish trades. Please try again."
        ),
      }
    }
  }

  return { ok: true, trades }
}
