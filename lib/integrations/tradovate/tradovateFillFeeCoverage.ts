import type { SupabaseClient } from "@supabase/supabase-js"
import { tradovateAuthedJsonRequest } from "@/lib/integrations/tradovate/tradovateApiClient"
import type { TradovateFillFeeRaw } from "./tradovateFillModels.ts"
import { TRADOVATE_LDEPS_BATCH_SIZE } from "./tradovateFillAcquisitionCore.ts"
import {
  emptyTradovateFillFeeTotals,
  fillFeeAvailabilityFromTotals,
  mergeTradovateFillFeeMaps,
  mergeTradovateFillFeeRecords,
  totalsFromTradovateFillFeeRaw,
  type TradovateFillFeeRecord,
} from "./tradovateFillFeeCoverageCore.ts"
import {
  mergeTradovateProviderMetadataFeeFields,
  readTradovateFillFeeFromProviderMetadata,
} from "./tradovateExecutionProviderMetadata.ts"

function idsQuery(ids: string[]): string {
  return ids.map((id) => encodeURIComponent(id)).join(",")
}

export function tradovateFillFeeRecordFromProviderMetadata(
  providerMetadata: unknown
): TradovateFillFeeRecord | null {
  const persisted = readTradovateFillFeeFromProviderMetadata(providerMetadata)
  if (!persisted) return null
  return persisted
}

export function loadPersistedTradovateFillFeesFromExecutions(
  rows: { external_fill_id: string; provider_metadata?: unknown }[]
): Map<string, TradovateFillFeeRecord> {
  const out = new Map<string, TradovateFillFeeRecord>()
  for (const row of rows) {
    const fillId = String(row.external_fill_id)
    const record = tradovateFillFeeRecordFromProviderMetadata(row.provider_metadata)
    if (record) out.set(fillId, record)
  }
  return out
}

export async function fetchTradovateFillFeesWithAvailability(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string,
  fillIds: string[]
): Promise<{
  fees: Map<string, TradovateFillFeeRecord>
  batchErrors: string[]
}> {
  const unique = [...new Set(fillIds.filter(Boolean))]
  const fees = new Map<string, TradovateFillFeeRecord>()
  const batchErrors: string[] = []

  if (unique.length === 0) return { fees, batchErrors }

  for (let i = 0; i < unique.length; i += TRADOVATE_LDEPS_BATCH_SIZE) {
    const batch = unique.slice(i, i + TRADOVATE_LDEPS_BATCH_SIZE)
    const path = `/v1/fillFee/ldeps?masterids=${idsQuery(batch)}`
    try {
      const rows = await tradovateAuthedJsonRequest<TradovateFillFeeRaw[]>(
        supabase,
        userId,
        connectionId,
        path
      )
      const seenInBatch = new Set<string>()
      if (Array.isArray(rows)) {
        for (const fee of rows) {
          const fillId =
            fee.id != null
              ? String(fee.id)
              : fee.fillId != null
                ? String(fee.fillId)
                : fee.masterid != null
                  ? String(fee.masterid)
                  : null
          if (!fillId) continue
          seenInBatch.add(fillId)
          const prev = fees.get(fillId)?.totals ?? emptyTradovateFillFeeTotals()
          const next = totalsFromTradovateFillFeeRaw(fee)
          const totals = {
            clearingFee: prev.clearingFee + next.clearingFee,
            exchangeFee: prev.exchangeFee + next.exchangeFee,
            nfaFee: prev.nfaFee + next.nfaFee,
            commission: prev.commission + next.commission,
          }
          fees.set(fillId, {
            totals,
            availability: fillFeeAvailabilityFromTotals(totals),
          })
        }
      }
      for (const fillId of batch) {
        if (seenInBatch.has(fillId)) continue
        fees.set(fillId, {
          totals: emptyTradovateFillFeeTotals(),
          availability: "KNOWN_ZERO",
        })
      }
    } catch (err) {
      const detail =
        err instanceof Error ? err.message.slice(0, 160) : "batch_request_failed"
      batchErrors.push(`batch_${i / TRADOVATE_LDEPS_BATCH_SIZE}:${detail}`)
      for (const fillId of batch) {
        fees.set(fillId, {
          totals: emptyTradovateFillFeeTotals(),
          availability: "UNAVAILABLE",
        })
      }
    }
  }

  return { fees, batchErrors }
}

export async function resolveTradovateFillFeesForSync(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
    fillIds: string[]
    executionRows: { external_fill_id: string; provider_metadata?: unknown }[]
  }
): Promise<{
  fees: Map<string, TradovateFillFeeRecord>
  batchErrors: string[]
}> {
  const persisted = loadPersistedTradovateFillFeesFromExecutions(params.executionRows)
  const { fees: fetched, batchErrors } = await fetchTradovateFillFeesWithAvailability(
    supabase,
    params.userId,
    params.connectionId,
    params.fillIds
  )

  const merged = mergeTradovateFillFeeMaps(persisted, fetched)

  for (const fillId of params.fillIds) {
    if (!merged.has(fillId)) {
      merged.set(fillId, {
        totals: emptyTradovateFillFeeTotals(),
        availability: "UNAVAILABLE",
      })
    }
  }

  return { fees: merged, batchErrors }
}

export function providerMetadataWithPersistedFillFee(
  existing: unknown,
  fillId: string,
  record: TradovateFillFeeRecord | undefined
): Record<string, unknown> {
  if (!record || record.availability === "UNAVAILABLE") {
    const prev = tradovateFillFeeRecordFromProviderMetadata(existing)
    if (prev && prev.availability !== "UNAVAILABLE") {
      return mergeTradovateProviderMetadataFeeFields(existing, prev)
    }
    return (
      existing && typeof existing === "object"
        ? { ...(existing as Record<string, unknown>) }
        : {}
    ) as Record<string, unknown>
  }
  return mergeTradovateProviderMetadataFeeFields(existing, record)
}

export function mergePersistedFillFeeOnDuplicate(
  existingMeta: unknown,
  incoming: TradovateFillFeeRecord | undefined
): Record<string, unknown> {
  const prev = tradovateFillFeeRecordFromProviderMetadata(existingMeta)
  const merged = mergeTradovateFillFeeRecords(prev, incoming)
  return mergeTradovateProviderMetadataFeeFields(existingMeta, merged)
}
