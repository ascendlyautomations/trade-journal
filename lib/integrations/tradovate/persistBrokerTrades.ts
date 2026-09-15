import type { SupabaseClient } from "@supabase/supabase-js"
import { getSessionFromDate } from "@/lib/getSession"
import type { ReconstructedLifecycleTrade } from "@/lib/integrations/tradovate/tradeReconstruction"
import {
  computeFuturesGrossPnl,
  sumFillFees,
} from "@/lib/integrations/tradovate/tradeReconstruction"
import type { ResolvedTradovateContract } from "@/lib/integrations/tradovate/tradovateMarketDataClient"

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

export async function upsertReconstructedBrokerTrades(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
    mappingId: string
    account: CanonicalAccountSnapshot
    completed: ReconstructedLifecycleTrade[]
    contracts: Map<string, ResolvedTradovateContract>
    feesByFillId: Map<
      string,
      { clearingFee: number; exchangeFee: number; nfaFee: number; commission: number }
    >
  }
): Promise<{
  tradesCreated: number
  tradesUpdated: number
  newTradeIds: string[]
  updatedTradeIds: string[]
}> {
  let tradesCreated = 0
  let tradesUpdated = 0
  const newTradeIds: string[] = []
  const updatedTradeIds: string[] = []
  const nowIso = new Date().toISOString()
  const modeDisplay = String(params.account.mode ?? "Live").trim() || "Live"
  const accountType = modeDisplay.toLowerCase()

  for (const lifecycle of params.completed) {
    const contract = params.contracts.get(lifecycle.contractId)
    const ticker = contract?.symbolRoot ?? lifecycle.contractId
    const valuePerPoint = contract?.valuePerPoint

    let pnl: number | null = null
    if (valuePerPoint != null && valuePerPoint > 0) {
      const gross = computeFuturesGrossPnl(
        lifecycle.direction,
        lifecycle.entryPrice,
        lifecycle.exitPrice,
        lifecycle.contracts,
        valuePerPoint
      )
      const fees = sumFillFees(params.feesByFillId, lifecycle.fillIds)
      pnl = gross - fees
    }

    const { duration_seconds, duration_text } = durationFromIso(
      lifecycle.entryTime,
      lifecycle.exitTime
    )
    const session = getSessionFromDate(lifecycle.entryTime) || "NY"
    const tradeDate = tradeDateFromIso(lifecycle.entryTime)

    const brokerRow = {
      user_id: params.userId,
      ticker,
      direction: lifecycle.direction,
      pnl,
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
      import_source: "tradovate",
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

    const { data: existing } = await supabase
      .from("trades")
      .select("id")
      .eq("user_id", params.userId)
      .eq("broker_lifecycle_id", lifecycle.lifecycleKey)
      .maybeSingle()

    if (existing?.id) {
      const patch: Record<string, unknown> = { ...brokerRow }
      for (const key of USER_AUTHORITATIVE_TRADE_FIELDS) {
        delete patch[key]
      }
      delete patch.created_at
      const { error } = await supabase
        .from("trades")
        .update(patch)
        .eq("id", existing.id)
        .eq("user_id", params.userId)
      if (!error) {
        tradesUpdated += 1
        updatedTradeIds.push(String(existing.id))
      }

      await supabase
        .from("broker_integration_executions")
        .update({
          lifecycle_key: lifecycle.lifecycleKey,
          canonical_trade_id: existing.id,
          updated_at: nowIso,
        })
        .eq("broker_integration_account_id", params.mappingId)
        .in("external_fill_id", lifecycle.fillIds.map((id) => Number(id)))
      continue
    }

    const { data: inserted, error } = await supabase
      .from("trades")
      .insert([brokerRow])
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
        updated_at: nowIso,
      })
      .eq("broker_integration_account_id", params.mappingId)
      .in(
        "external_fill_id",
        lifecycle.fillIds.map((id) => Number(id))
      )
  }

  return { tradesCreated, tradesUpdated, newTradeIds, updatedTradeIds }
}
