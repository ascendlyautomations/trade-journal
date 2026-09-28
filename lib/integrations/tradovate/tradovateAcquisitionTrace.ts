import type { SupabaseClient } from "@supabase/supabase-js"
import type { TradovateApiEnvironment } from "./tradovateOAuthEnv.ts"
import { getTradovateRestBaseUrl } from "./tradovateOAuthEnv.ts"
import type { TradovateFillRaw, TradovateOrderRaw } from "./tradovateFillModels.ts"
import { tradovateFillStableId } from "./tradovateFillModels.ts"
import { filterParsedTradovateFillsForAccount } from "./tradovateOrderAccountMap.ts"

export function tradovateAcquisitionTraceEnabled(): boolean {
  return process.env.TRADOVATE_ACQUISITION_TRACE === "1"
}

async function loadReferenceFillIdsForExternalAccount(
  supabase: SupabaseClient,
  params: {
    externalAccountId: string
    excludeUserId: string
  }
): Promise<string[]> {
  const { data: mappings } = await supabase
    .from("broker_integration_accounts")
    .select("id")
    .eq("provider", "tradovate")
    .eq("external_account_id", params.externalAccountId)

  const mappingIds = (mappings ?? []).map((r) => String(r.id))
  if (mappingIds.length === 0) return []

  const { data: rows } = await supabase
    .from("broker_integration_executions")
    .select("external_fill_id")
    .eq("provider", "tradovate")
    .neq("user_id", params.excludeUserId)
    .in("broker_integration_account_id", mappingIds)

  const ids = new Set<string>()
  for (const row of rows ?? []) {
    const id = String(row.external_fill_id ?? "").trim()
    if (id) ids.add(id)
  }
  return [...ids]
}

function countFillIdsInRaw(fills: TradovateFillRaw[], reference: Set<string>): number {
  let n = 0
  for (const fill of fills) {
    const id = tradovateFillStableId(fill)
    if (reference.has(id)) n += 1
  }
  return n
}

function countFillIdsInMerged(fills: TradovateFillRaw[], reference: Set<string>): number {
  return countFillIdsInRaw(fills, reference)
}

export async function logTradovateAcquisitionTrace(params: {
  supabase: SupabaseClient
  mappingId: string
  connectionId: string
  userId: string
  externalAccountId: string
  apiEnvironment: TradovateApiEnvironment
  ordersFromDeps: TradovateOrderRaw[]
  orderIdsFromDeps: string[]
  fillsFromLdeps: TradovateFillRaw[]
  fillsFromList: TradovateFillRaw[]
  ordersFromList: TradovateOrderRaw[]
  fillsFromItemsRepair: TradovateFillRaw[]
  orderAccountById: Map<string, string>
  mergedAccountFills: TradovateFillRaw[]
  acquisitionErrors: string[]
  orderDepsFailed: boolean
  fillListFailed: boolean
  fillLdepsBatchErrors: number
}): Promise<void> {
  if (!tradovateAcquisitionTraceEnabled()) return

  const baseHost = new URL(getTradovateRestBaseUrl(params.apiEnvironment)).host
  const target = params.externalAccountId

  const orderDepsAccountMatchedCount = params.ordersFromDeps.filter(
    (o) => o.accountId != null && String(o.accountId) === target
  ).length

  const fillLdepsRawCount = params.fillsFromLdeps.length
  const fillLdepsAccountMatchedCount = params.fillsFromLdeps.filter((fill) => {
    if (fill.orderId == null) return false
    return params.orderAccountById.get(String(fill.orderId)) === target
  }).length

  const fillListRawCount = params.fillsFromList.length
  const fillListAccountMatchedCount = filterParsedTradovateFillsForAccount(
    params.fillsFromList,
    target,
    params.orderAccountById
  ).length

  const orderListRawCount = params.ordersFromList.length
  const orderListAccountMatchedCount = params.ordersFromList.filter(
    (o) => o.accountId != null && String(o.accountId) === target
  ).length

  const repairFillCount = params.fillsFromItemsRepair.length
  const mergedUniqueFillCount = params.mergedAccountFills.length

  const referenceFillIds = await loadReferenceFillIdsForExternalAccount(
    params.supabase,
    {
      externalAccountId: target,
      excludeUserId: params.userId,
    }
  )
  const referenceSet = new Set(referenceFillIds)
  const referenceKnownCount = referenceSet.size
  const referenceInFillList = countFillIdsInRaw(params.fillsFromList, referenceSet)
  const referenceInFillLdeps = countFillIdsInRaw(params.fillsFromLdeps, referenceSet)
  const referenceInMerged = countFillIdsInMerged(
    params.mergedAccountFills,
    referenceSet
  )

  console.info(
    [
      "[TRADOVATE_ACQUISITION_TRACE]",
      `mappingId=${params.mappingId}`,
      `connectionId=${params.connectionId}`,
      `environment=${params.apiEnvironment}`,
      `baseHost=${baseHost}`,
      `externalAccountId=${target}`,
      `orderDepsCount=${params.ordersFromDeps.length}`,
      `orderDepsAccountMatchedCount=${orderDepsAccountMatchedCount}`,
      `orderIdsForLdeps=${params.orderIdsFromDeps.length}`,
      `fillLdepsRawCount=${fillLdepsRawCount}`,
      `fillLdepsAccountMatchedCount=${fillLdepsAccountMatchedCount}`,
      `fillListRawCount=${fillListRawCount}`,
      `fillListAccountMatchedCount=${fillListAccountMatchedCount}`,
      `orderListRawCount=${orderListRawCount}`,
      `orderListAccountMatchedCount=${orderListAccountMatchedCount}`,
      `repairFillCount=${repairFillCount}`,
      `mergedUniqueFillCount=${mergedUniqueFillCount}`,
      `referenceKnownFillIds=${referenceKnownCount}`,
      `referenceInFillList=${referenceInFillList}`,
      `referenceInFillLdeps=${referenceInFillLdeps}`,
      `referenceInMerged=${referenceInMerged}`,
      `orderDepsFailed=${params.orderDepsFailed}`,
      `fillListFailed=${params.fillListFailed}`,
      `fillLdepsBatchErrors=${params.fillLdepsBatchErrors}`,
      `acquisitionErrorCount=${params.acquisitionErrors.length}`,
    ].join(" ")
  )

  if (params.acquisitionErrors.length > 0) {
    console.info(
      `[TRADOVATE_ACQUISITION_TRACE] acquisitionErrors=${params.acquisitionErrors
        .map((e) => e.slice(0, 120))
        .join("|")}`
    )
  }
}
