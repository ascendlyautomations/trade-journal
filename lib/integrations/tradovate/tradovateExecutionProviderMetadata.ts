import type { TradovateMetadataQuality } from "./tradovateMetadataQuality.ts"
import type {
  TradovateFillFeeAvailability,
  TradovateFillFeeRecord,
  TradovateFillFeeTotals,
} from "./tradovateFillFeeCoverageCore.ts"
import {
  emptyTradovateFillFeeTotals,
  fillFeeAvailabilityFromTotals,
} from "./tradovateFillFeeCoverageCore.ts"

export type TradovateExecutionContractMetadataPersisted = {
  valuePerPoint?: number | null
  tickSize?: number | null
  metadataQuality?: TradovateMetadataQuality | null
  productName?: string | null
}

function finitePositive(n: unknown): number | null {
  if (n == null) return null
  const v = Number(n)
  return Number.isFinite(v) && v > 0 ? v : null
}

export function readTradovateContractMetadataFromProviderMetadata(
  providerMetadata: unknown
): TradovateExecutionContractMetadataPersisted {
  if (!providerMetadata || typeof providerMetadata !== "object") return {}
  const root = providerMetadata as Record<string, unknown>
  const nested =
    root.tradovateContract && typeof root.tradovateContract === "object"
      ? (root.tradovateContract as Record<string, unknown>)
      : root

  const quality = nested.metadataQuality
  const metadataQuality =
    quality === "RESOLVED_PRODUCT" ||
    quality === "RESOLVED_CONTRACT" ||
    quality === "PERSISTED_VALID_HINT" ||
    quality === "LOCAL_FALLBACK" ||
    quality === "UNRESOLVED"
      ? quality
      : null

  return {
    valuePerPoint: finitePositive(nested.valuePerPoint),
    tickSize: finitePositive(nested.tickSize),
    metadataQuality,
    productName:
      typeof nested.productName === "string" ? nested.productName : null,
  }
}

export function mergeTradovateProviderMetadataContractFields(
  existing: unknown,
  incoming: TradovateExecutionContractMetadataPersisted
): Record<string, unknown> {
  const base =
    existing && typeof existing === "object"
      ? { ...(existing as Record<string, unknown>) }
      : {}
  const prev =
    base.tradovateContract && typeof base.tradovateContract === "object"
      ? { ...(base.tradovateContract as Record<string, unknown>) }
      : {}

  base.tradovateContract = {
    ...prev,
    ...(incoming.valuePerPoint != null ? { valuePerPoint: incoming.valuePerPoint } : {}),
    ...(incoming.tickSize != null ? { tickSize: incoming.tickSize } : {}),
    ...(incoming.metadataQuality ? { metadataQuality: incoming.metadataQuality } : {}),
    ...(incoming.productName ? { productName: incoming.productName } : {}),
  }
  return base
}

export function readTradovateFillFeeFromProviderMetadata(
  providerMetadata: unknown
): TradovateFillFeeRecord | null {
  if (!providerMetadata || typeof providerMetadata !== "object") return null
  const root = providerMetadata as Record<string, unknown>
  const nested =
    root.tradovateFees && typeof root.tradovateFees === "object"
      ? (root.tradovateFees as Record<string, unknown>)
      : null
  if (!nested) return null

  const availability = nested.availability
  const parsedAvailability: TradovateFillFeeAvailability | null =
    availability === "KNOWN_VALUE" ||
    availability === "KNOWN_ZERO" ||
    availability === "UNAVAILABLE"
      ? availability
      : null

  const totals: TradovateFillFeeTotals = {
    clearingFee: Number(nested.clearingFee ?? 0) || 0,
    exchangeFee: Number(nested.exchangeFee ?? 0) || 0,
    nfaFee: Number(nested.nfaFee ?? 0) || 0,
    commission: Number(nested.commission ?? 0) || 0,
  }

  if (!parsedAvailability) return null
  return {
    totals,
    availability: parsedAvailability,
  }
}

export function mergeTradovateProviderMetadataFeeFields(
  existing: unknown,
  record: TradovateFillFeeRecord
): Record<string, unknown> {
  const base =
    existing && typeof existing === "object"
      ? { ...(existing as Record<string, unknown>) }
      : {}
  const prev =
    base.tradovateFees && typeof base.tradovateFees === "object"
      ? { ...(base.tradovateFees as Record<string, unknown>) }
      : {}

  if (
    prev.availability &&
    prev.availability !== "UNAVAILABLE" &&
    record.availability === "UNAVAILABLE"
  ) {
    return base
  }

  const totals =
    record.availability === "UNAVAILABLE"
      ? {
          clearingFee: Number(prev.clearingFee ?? 0) || 0,
          exchangeFee: Number(prev.exchangeFee ?? 0) || 0,
          nfaFee: Number(prev.nfaFee ?? 0) || 0,
          commission: Number(prev.commission ?? 0) || 0,
        }
      : record.totals

  const availability =
    record.availability === "UNAVAILABLE" && prev.availability
      ? (prev.availability as TradovateFillFeeAvailability)
      : record.availability

  base.tradovateFees = {
    ...prev,
    clearingFee: totals.clearingFee,
    exchangeFee: totals.exchangeFee,
    nfaFee: totals.nfaFee,
    commission: totals.commission,
    availability:
      availability ??
      fillFeeAvailabilityFromTotals(totals),
  }
  return base
}
