import type { SupabaseClient } from "@supabase/supabase-js"
import { normalizeFuturesSymbol } from "@/lib/normalizeFuturesSymbol"
import { tradovateAuthedJsonRequest } from "@/lib/integrations/tradovate/tradovateApiClient"
import type {
  TradovateContractMaturityRaw,
  TradovateContractRaw,
  TradovateFillFeeRaw,
  TradovateFillRaw,
  TradovateOrderRaw,
  TradovateProductRaw,
} from "@/lib/integrations/tradovate/tradovateFillModels"

const ID_BATCH = 40

function idsQuery(ids: string[]): string {
  return ids.map((id) => encodeURIComponent(id)).join(",")
}

async function fetchItems<T>(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string,
  entity: string,
  ids: string[]
): Promise<T[]> {
  if (ids.length === 0) return []
  const out: T[] = []
  for (let i = 0; i < ids.length; i += ID_BATCH) {
    const batch = ids.slice(i, i + ID_BATCH)
    const path = `/v1/${entity}/items?ids=${idsQuery(batch)}`
    const rows = await tradovateAuthedJsonRequest<unknown[]>(
      supabase,
      userId,
      connectionId,
      path
    )
    if (Array.isArray(rows)) out.push(...(rows as T[]))
  }
  return out
}

/** Official Tradovate REST: GET /v1/fill/list (Fill entities for authenticated user). */
export async function fetchTradovateFillList(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string
): Promise<TradovateFillRaw[]> {
  const body = await tradovateAuthedJsonRequest<unknown>(
    supabase,
    userId,
    connectionId,
    "/v1/fill/list"
  )
  if (!Array.isArray(body)) return []
  return body.filter((row) => row && typeof row === "object") as TradovateFillRaw[]
}

/** Official Tradovate REST: GET /v1/order/list (Order entities — includes accountId). */
export async function fetchTradovateOrderList(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string
): Promise<TradovateOrderRaw[]> {
  const body = await tradovateAuthedJsonRequest<unknown>(
    supabase,
    userId,
    connectionId,
    "/v1/order/list"
  )
  if (!Array.isArray(body)) return []
  return body.filter((row) => row && typeof row === "object") as TradovateOrderRaw[]
}

export async function fetchTradovateOrdersByIds(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string,
  orderIds: string[]
): Promise<TradovateOrderRaw[]> {
  return fetchItems<TradovateOrderRaw>(
    supabase,
    userId,
    connectionId,
    "order",
    orderIds
  )
}

export async function fetchTradovateContractsByIds(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string,
  contractIds: string[]
): Promise<TradovateContractRaw[]> {
  return fetchItems<TradovateContractRaw>(
    supabase,
    userId,
    connectionId,
    "contract",
    contractIds
  )
}

export async function fetchTradovateContractMaturitiesByIds(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string,
  maturityIds: string[]
): Promise<TradovateContractMaturityRaw[]> {
  return fetchItems<TradovateContractMaturityRaw>(
    supabase,
    userId,
    connectionId,
    "contractMaturity",
    maturityIds
  )
}

export async function fetchTradovateProductsByIds(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string,
  productIds: string[]
): Promise<TradovateProductRaw[]> {
  return fetchItems<TradovateProductRaw>(
    supabase,
    userId,
    connectionId,
    "product",
    productIds
  )
}

/** Official Tradovate REST: GET /v1/fillFee/ldeps?masterids=… */
export async function fetchTradovateFillFeesForFillIds(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string,
  fillIds: string[]
): Promise<Map<string, { clearingFee: number; exchangeFee: number; nfaFee: number; commission: number }>> {
  const result = new Map<
    string,
    { clearingFee: number; exchangeFee: number; nfaFee: number; commission: number }
  >()
  if (fillIds.length === 0) return result

  // One (or few) batched ldeps calls — avoids N auth handshakes that were
  // racing OAuth refresh against the same connection mid-sync.
  const unique = [...new Set(fillIds)]
  const BATCH = 40
  for (let i = 0; i < unique.length; i += BATCH) {
    const batch = unique.slice(i, i + BATCH)
    const path = `/v1/fillFee/ldeps?masterids=${idsQuery(batch)}`
    const rows = await tradovateAuthedJsonRequest<TradovateFillFeeRaw[]>(
      supabase,
      userId,
      connectionId,
      path
    )
    if (!Array.isArray(rows) || rows.length === 0) continue
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
      const prev = result.get(fillId) ?? {
        clearingFee: 0,
        exchangeFee: 0,
        nfaFee: 0,
        commission: 0,
      }
      prev.clearingFee += Number(fee.clearingFee ?? 0) || 0
      prev.exchangeFee += Number(fee.exchangeFee ?? 0) || 0
      prev.nfaFee += Number(fee.nfaFee ?? 0) || 0
      prev.commission += Number(fee.commission ?? 0) || 0
      result.set(fillId, prev)
    }
  }
  return result
}

export type ResolvedTradovateContract = {
  contractId: string
  contractName: string
  symbolRoot: string
  valuePerPoint: number | null
}

export async function resolveTradovateContracts(
  supabase: SupabaseClient,
  userId: string,
  connectionId: string,
  contractIds: string[]
): Promise<Map<string, ResolvedTradovateContract>> {
  const unique = [...new Set(contractIds.filter(Boolean))]
  const contracts = await fetchTradovateContractsByIds(
    supabase,
    userId,
    connectionId,
    unique
  )
  const maturityIds = [
    ...new Set(
      contracts
        .map((c) => (c.contractMaturityId != null ? String(c.contractMaturityId) : ""))
        .filter(Boolean)
    ),
  ]
  const maturities = await fetchTradovateContractMaturitiesByIds(
    supabase,
    userId,
    connectionId,
    maturityIds
  )
  const productIds = [
    ...new Set(
      maturities
        .map((m) => (m.productId != null ? String(m.productId) : ""))
        .filter(Boolean)
    ),
  ]
  const products = await fetchTradovateProductsByIds(
    supabase,
    userId,
    connectionId,
    productIds
  )

  const productById = new Map(
    products.map((p) => [String(p.id), p] as const)
  )
  const maturityById = new Map(
    maturities.map((m) => [String(m.id), m] as const)
  )

  const resolved = new Map<string, ResolvedTradovateContract>()
  for (const contract of contracts) {
    const contractId = String(contract.id)
    const contractName = String(contract.name ?? "").trim()
    const maturity = maturityById.get(String(contract.contractMaturityId ?? ""))
    const product = maturity
      ? productById.get(String(maturity.productId ?? ""))
      : undefined
    const productName = product?.name?.trim() || contractName
    const symbolRoot =
      normalizeFuturesSymbol(productName) || normalizeFuturesSymbol(contractName)
    const valuePerPoint =
      product?.valuePerPoint != null && Number.isFinite(Number(product.valuePerPoint))
        ? Number(product.valuePerPoint)
        : null
    const resolvedRoot =
      symbolRoot ||
      (contractName && !/^\d+$/.test(contractName) ? contractName : "")
    resolved.set(contractId, {
      contractId,
      contractName,
      symbolRoot: resolvedRoot || contractId,
      valuePerPoint,
    })
  }
  return resolved
}
