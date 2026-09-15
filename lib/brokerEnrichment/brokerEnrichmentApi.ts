import type { SupabaseClient } from "@supabase/supabase-js"
import { parseOptionalRr } from "@/lib/tradeRr"
import {
  BROKER_ENRICHMENT_TRADE_SELECT,
  type BrokerEnrichmentTradeRow,
} from "@/lib/brokerEnrichment/brokerEnrichmentTypes"

export async function fetchBrokerEnrichmentTradesByIds(
  client: SupabaseClient,
  userId: string,
  tradeIds: string[]
): Promise<BrokerEnrichmentTradeRow[]> {
  const ids = [...new Set(tradeIds.map((id) => id.trim()).filter(Boolean))]
  if (ids.length === 0) return []

  const { data, error } = await client
    .from("trades")
    .select(BROKER_ENRICHMENT_TRADE_SELECT)
    .eq("user_id", userId)
    .in("id", ids)
    .eq("import_source", "tradovate")
    .eq("broker_enrichment_status", "pending")

  if (error || !data) return []

  const byId = new Map(data.map((row) => [String(row.id), row as BrokerEnrichmentTradeRow]))
  return ids.map((id) => byId.get(id)).filter((row): row is BrokerEnrichmentTradeRow => row != null)
}

export async function saveBrokerTradeEnrichment(
  client: SupabaseClient,
  userId: string,
  tradeId: string,
  input: { rr: string; notes: string }
): Promise<{ ok: true } | { ok: false; message: string }> {
  const rrRaw = input.rr.trim()
  const parsedRr = rrRaw ? parseOptionalRr(rrRaw) : null
  if (rrRaw && parsedRr === null) {
    return { ok: false, message: "Enter a valid risk/reward value or leave RR blank." }
  }

  const { error } = await client
    .from("trades")
    .update({
      rr: parsedRr,
      notes: input.notes.trim() || null,
      broker_enrichment_status: "completed",
      reviewed: true,
    })
    .eq("id", tradeId)
    .eq("user_id", userId)
    .eq("import_source", "tradovate")
    .eq("broker_enrichment_status", "pending")

  if (error) {
    return { ok: false, message: "Could not save trade details." }
  }
  return { ok: true }
}

export async function dismissBrokerTradeEnrichment(
  client: SupabaseClient,
  userId: string,
  tradeId: string
): Promise<boolean> {
  const { error } = await client
    .from("trades")
    .update({
      broker_enrichment_status: "dismissed",
      reviewed: true,
    })
    .eq("id", tradeId)
    .eq("user_id", userId)
    .eq("import_source", "tradovate")
    .eq("broker_enrichment_status", "pending")

  return !error
}
