export type BrokerEnrichmentStatus = "pending" | "completed" | "dismissed"

export type BrokerEnrichmentTradeRow = {
  id: string
  ticker: string | null
  direction: string | null
  pnl: number | string | null
  contracts: number | null
  entry_time: string | null
  exit_time: string | null
  entry_price: number | null
  exit_price: number | null
  duration_seconds: number | null
  account_name: string | null
  account_id: string | null
  notes: string | null
  rr: number | null
  import_source: string | null
  broker_enrichment_status: BrokerEnrichmentStatus | null
}

export const BROKER_ENRICHMENT_TRADE_SELECT =
  "id,ticker,direction,pnl,contracts,entry_time,exit_time,entry_price,exit_price,duration_seconds,account_name,account_id,notes,rr,import_source,broker_enrichment_status"

export const BROKER_ENRICHMENT_QUEUE_EVENT = "tj-broker-enrichment-queue"
