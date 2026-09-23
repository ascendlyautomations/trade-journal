import type { SupabaseClient } from "@supabase/supabase-js"
import { getSessionFromDate } from "@/lib/getSession"
import { findCanonicalTradeIdForBrokerFillIds } from "@/lib/integrations/brokerExecutionIdentity"
import type { ReconstructedLifecycleTrade } from "@/lib/integrations/tradovate/tradeReconstruction"
import { mergeBrokerTradeFinancialFields } from "@/lib/integrations/tradovate/brokerTradeAuthoritativeMerge"
import { logTradovatePnLTrace } from "@/lib/integrations/tradovate/tradovatePnLDebugLog"
import {
  computeTradovateBrokerTradeFinancials,
  type BrokerContractMeta,
} from "@/lib/integrations/tradovate/tradovateBrokerTradeFinancials"

export type CanonicalAccountSnapshot = {
  id: string
  name: string
  account_size: string | null
  mode: string | null
  category: string | null
}

const USER_AUTHORITATIVE_TRADE_FIELDS = new Set([
  "notes",
  "psychology_notes",
  "public_description",
  "image_url",
  "is_public",
  "strategy",
  "confidence",
  "emotion",
  "exit_emotion",
  "followed_plan",
  "mistake_type",
  "market_condition",
  "news_event",
  "timeframe",
  "trade_type",
  "execution_rating",
  "top_confluences",
  "ai_feedback",
  "ai_feedback_created_at",
  "reviewed",
  "is_pinned",
  "rr",
  "broker_enrichment_status",
  "reviewed",
])

function durationFromIso(entry: string, exit: string): {
  duration_seconds: number | null
  duration_text: string | null
} {
  const a = new Date(entry).getTime()
  const b = new Date(exit).getTime()
  if (Number.isNaN(a) || Number.isNaN(b) || b < a) {
    return { duration_seconds: null, duration_text: null }
  }
  const duration_seconds = Math.round((b - a) / 1000)
  return { duration_seconds, duration_text: null }
}

function tradeDateFromIso(iso: string): string {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return new Date().toISOString().slice(0, 10)
  return d.toISOString().slice(0, 10)
}

export type { BrokerContractMeta } from "@/lib/integrations/tradovate/tradovateBrokerTradeFinancials"

export async function upsertReconstructedBrokerTrades(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
    mappingId: string
    externalBrokerAccountId: string
    account: CanonicalAccountSnapshot
    completed: ReconstructedLifecycleTrade[]
    contracts: Map<string, BrokerContractMeta>
    feesByFillId:
      | Map<
          string,
          { clearingFee: number; exchangeFee: number; nfaFee: number; commission: number }
        >
      | Map<
          string,
          import("@/lib/integrations/tradovate/tradovateFillFeeCoverageCore").TradovateFillFeeRecord
        >
    importSource?: "tradovate" | "rithmic"
  }
): Promise<{
  tradesCreated: number
  tradesUpdated: number
  newTradeIds: string[]
  updatedTradeIds: string[]
  tradesWithPnL: number
  tradesWithoutPnL: number
  numericTickersPersisted: number
}> {
  let tradesCreated = 0
  let tradesUpdated = 0
  let tradesWithPnL = 0
  let tradesWithoutPnL = 0
  let numericTickersPersisted = 0
  const newTradeIds: string[] = []
  const updatedTradeIds: string[] = []
  const nowIso = new Date().toISOString()
  const modeDisplay = String(params.account.mode ?? "Live").trim() || "Live"
  const accountType = modeDisplay.toLowerCase()
  const importSource = params.importSource ?? "tradovate"

  for (const lifecycle of params.completed) {
    const contractIdKey = String(lifecycle.contractId).trim()
    const contract =
      params.contracts.get(contractIdKey) ??
      params.contracts.get(lifecycle.contractId)
    const financials = computeTradovateBrokerTradeFinancials({
      lifecycle,
      contract,
      contractIdKey,
      feesByFillId: params.feesByFillId,
    })
    const incomingTicker = financials.ticker
    const incomingPnL = financials.netPnL

    const { duration_seconds, duration_text } = durationFromIso(
      lifecycle.entryTime,
      lifecycle.exitTime
    )
    const session = getSessionFromDate(lifecycle.entryTime) || "NY"
    const tradeDate = tradeDateFromIso(lifecycle.entryTime)

    const brokerRow = {
      user_id: params.userId,
      ticker: incomingTicker,
      direction: lifecycle.direction,
      pnl: incomingPnL,
      points: lifecycle.points,
      contracts: lifecycle.contracts,
      entry_price: lifecycle.entryPrice,
      exit_price: lifecycle.exitPrice,
      entry_time: lifecycle.entryTime,
      exit_time: lifecycle.exitTime,
      duration_seconds,
      duration_text,
      session,
      trade_date: tradeDate,
      date: lifecycle.exitTime,
      created_at: lifecycle.exitTime,
      account_id: params.account.id,
      account_name: params.account.name,
      account_size: params.account.account_size,
      mode: modeDisplay,
      account_type: accountType,
      account_category: params.account.category,
      import_source: importSource,
      import_fingerprint: lifecycle.lifecycleKey,
      broker_connection_id: params.connectionId,
      broker_integration_account_id: params.mappingId,
      broker_lifecycle_id: lifecycle.lifecycleKey,
      last_broker_sync_at: nowIso,
      is_public: false,
      public_description: "",
      image_url: null,
      broker_enrichment_status: "pending",
      reviewed: false,
    }

    const { data: existingByLifecycle } = await supabase
      .from("trades")
      .select("id, pnl, ticker")
      .eq("user_id", params.userId)
      .eq("broker_lifecycle_id", lifecycle.lifecycleKey)
      .maybeSingle()

    let existingTradeId =
      (existingByLifecycle?.id ? String(existingByLifecycle.id) : null) ??
      (await findCanonicalTradeIdForBrokerFillIds(supabase, {
        userId: params.userId,
        provider: importSource,
        fillIds: lifecycle.fillIds,
      }))

    let existingStoredPnL =
      existingByLifecycle?.pnl != null ? Number(existingByLifecycle.pnl) : null
    let existingTicker = existingByLifecycle?.ticker ?? null

    if (
      existingTradeId &&
      existingByLifecycle?.id == null &&
      (existingStoredPnL == null || !existingTicker)
    ) {
      const { data: existingById } = await supabase
        .from("trades")
        .select("pnl, ticker")
        .eq("user_id", params.userId)
        .eq("id", existingTradeId)
        .maybeSingle()
      if (existingById) {
        existingStoredPnL =
          existingById.pnl != null ? Number(existingById.pnl) : existingStoredPnL
        existingTicker = existingById.ticker ?? existingTicker
      }
    }

    const mergedFinancials =
      existingTradeId != null
        ? mergeBrokerTradeFinancialFields({
            existingPnL: existingStoredPnL,
            existingTicker,
            incomingPnL,
            incomingTicker,
          })
        : {
            finalPnL: incomingPnL,
            finalTicker: incomingTicker,
            decision: "insert_incoming",
          }

    const ticker = mergedFinancials.finalTicker
    const pnl = mergedFinancials.finalPnL
    if (/^\d+$/.test(String(ticker).trim())) numericTickersPersisted += 1
    if (pnl != null) tradesWithPnL += 1
    else tradesWithoutPnL += 1

    logTradovatePnLTrace({
      lifecycle,
      contract,
      contractIdKey,
      financials,
      existingStoredPnL,
      existingTicker,
      calculatedPnL: incomingPnL,
      incomingPnL,
      finalPnL: pnl,
      incomingTicker,
      finalTicker: ticker,
      decision: mergedFinancials.decision,
    })

    if (existingTradeId) {
      const patch: Record<string, unknown> = { ...brokerRow }
      patch.ticker = ticker
      patch.pnl = pnl
      for (const key of USER_AUTHORITATIVE_TRADE_FIELDS) {
        delete patch[key]
      }
      delete patch.created_at
      patch.broker_lifecycle_id = lifecycle.lifecycleKey
      patch.broker_integration_account_id = params.mappingId
      patch.broker_connection_id = params.connectionId
      const { error } = await supabase
        .from("trades")
        .update(patch)
        .eq("id", existingTradeId)
        .eq("user_id", params.userId)
      if (!error) {
        tradesUpdated += 1
        updatedTradeIds.push(existingTradeId)
      }

      await supabase
        .from("broker_integration_executions")
        .update({
          lifecycle_key: lifecycle.lifecycleKey,
          canonical_trade_id: existingTradeId,
          broker_integration_account_id: params.mappingId,
          connection_id: params.connectionId,
          updated_at: nowIso,
        })
        .eq("user_id", params.userId)
        .eq("provider", importSource)
        .in("external_fill_id", lifecycle.fillIds)
      continue
    }

    const insertRow = { ...brokerRow, ticker, pnl }
    const { data: inserted, error } = await supabase
      .from("trades")
      .insert([insertRow])
      .select("id")
      .single()

    if (error || !inserted) continue
    tradesCreated += 1
    newTradeIds.push(String(inserted.id))

    await supabase
      .from("broker_integration_executions")
      .update({
        lifecycle_key: lifecycle.lifecycleKey,
        canonical_trade_id: inserted.id,
        broker_integration_account_id: params.mappingId,
        connection_id: params.connectionId,
        updated_at: nowIso,
      })
      .eq("user_id", params.userId)
      .eq("provider", importSource)
      .in("external_fill_id", lifecycle.fillIds)
  }

  return {
    tradesCreated,
    tradesUpdated,
    newTradeIds,
    updatedTradeIds,
    tradesWithPnL,
    tradesWithoutPnL,
    numericTickersPersisted,
  }
}
