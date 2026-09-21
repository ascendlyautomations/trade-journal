/**
 * Phase 8B — canonical TradeSummary wire + Profile tab trades V2 envelope.
 */

export const TRADE_SUMMARY_SCHEMA = "trade_summary_v1" as const

export type TradeSummaryWireV1 = {
  summary_schema: typeof TRADE_SUMMARY_SCHEMA
  id: string
  user_id: string
  ticker?: string | null
  direction?: string | null
  pnl?: number | string | null
  rr?: number | string | null
  points?: number | string | null
  contracts?: number | string | null
  entry_time?: string | null
  exit_time?: string | null
  created_at: string
  is_public?: boolean
  public_description?: string | null
  note_preview?: string | null
  image_url?: string | null
  image_crop?: unknown
  image_display_mode?: string | null
  mode?: string | null
  account_type?: string | null
  trade_mode?: string | null
  duration_seconds?: number | string | null
  duration_text?: string | null
}

export type ProfileTabBootstrapMetaV2 = {
  contract_version: "v2"
  found: boolean
  server_time?: string
  viewer_id: string | null
}

export type EngagementSnapshotV1 = {
  like_count: number
  liked_by_me: boolean
  comment_count: number
}

export type ProfileTabBootstrapV2 = {
  meta: ProfileTabBootstrapMetaV2
  data: {
    tab: "trades"
    items: TradeSummaryWireV1[]
    engagement: Record<string, EngagementSnapshotV1>
    next_cursor: string | null
  }
}

export function assertProfileTabContractV2(
  meta: { contract_version?: string } | null | undefined
): void {
  if (!meta || meta.contract_version !== "v2") {
    throw new Error(
      `Profile tab trades V2 contract version mismatch: expected v2, got ${meta?.contract_version ?? "missing"}`
    )
  }
}

export function decodeProfileTabBootstrapV2(raw: unknown): ProfileTabBootstrapV2 {
  if (!raw || typeof raw !== "object" || !("meta" in raw) || !("data" in raw)) {
    throw new Error("ProfileTabBootstrapV2: expected { meta, data }")
  }
  const envelope = raw as ProfileTabBootstrapV2
  assertProfileTabContractV2(envelope.meta)
  if (envelope.data.tab !== "trades") {
    throw new Error(`ProfileTabBootstrapV2: expected tab trades, got ${envelope.data.tab}`)
  }
  if (!Array.isArray(envelope.data.items)) {
    throw new Error("ProfileTabBootstrapV2: items must be an array")
  }
  for (const item of envelope.data.items) {
    if (!item || typeof item !== "object") {
      throw new Error("ProfileTabBootstrapV2: invalid summary item")
    }
    const row = item as TradeSummaryWireV1
    if (row.summary_schema !== TRADE_SUMMARY_SCHEMA) {
      throw new Error(
        `TradeSummary schema mismatch: expected ${TRADE_SUMMARY_SCHEMA}, got ${String(row.summary_schema)}`
      )
    }
    if (!row.id || !row.user_id || !row.created_at) {
      throw new Error("TradeSummary missing id, user_id, or created_at")
    }
  }
  return envelope
}

/** UTF-8 byte length of JSON serialization (telemetry / shadow). */
export function payloadUtf8Bytes(value: unknown): number {
  return Buffer.byteLength(JSON.stringify(value), "utf8")
}
