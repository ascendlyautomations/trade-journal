import type { SupabaseClient } from "@supabase/supabase-js"
import type { TradovateFillRaw } from "./tradovateFillModels.ts"
import {
  fetchTradovateFillPairList,
  fetchTradovateFillPairsByPositionIdsLdeps,
  fetchTradovatePositionsByAccountDeps,
} from "./tradovateMarketDataClient.ts"
import {
  mergeAccountScopedTradovateFillPairs,
  completedTradovateFillPairs,
} from "./tradovateFillPairCore.ts"
import {
  normalizeTradovateFillPairRow,
  type NormalizedTradovateFillPair,
} from "./tradovateFillPairModels.ts"
import { logTradovateSync } from "./tradovateSyncLogger.ts"

export type TradovateFillPairAcquisitionResult = {
  fillPairs: NormalizedTradovateFillPair[]
  insufficientData: boolean
  acquisitionErrors: string[]
}

function normalizeFillPairRows(rows: unknown[]): NormalizedTradovateFillPair[] {
  const out: NormalizedTradovateFillPair[] = []
  for (const raw of rows) {
    if (!raw || typeof raw !== "object") continue
    const normalized = normalizeTradovateFillPairRow(raw as import("./tradovateFillPairModels.ts").TradovateFillPairRaw)
    if (normalized) out.push(normalized)
  }
  return out
}

function positionIdsFromAccountFills(accountFills: TradovateFillRaw[]): string[] {
  return [
    ...new Set(
      accountFills
        .map((f) => (f.positionId != null ? String(f.positionId) : ""))
        .filter(Boolean)
    ),
  ]
}

/**
 * Account-scoped FillPair validation acquisition:
 * position/deps(account) → fillPair/ldeps(positions) + supplemental fillPair/list.
 */
export async function acquireTradovateFillPairsForAccount(
  supabase: SupabaseClient,
  params: {
    userId: string
    connectionId: string
    targetAccountId: string
    mappingId: string
    trigger: string
    accountFills: TradovateFillRaw[]
  }
): Promise<TradovateFillPairAcquisitionResult> {
  const acquisitionErrors: string[] = []
  let positionDepsFailed = false
  let fillPairLdepsBatchErrors = 0

  let positionIds: string[] = []
  try {
    const positions = await fetchTradovatePositionsByAccountDeps(
      supabase,
      params.userId,
      params.connectionId,
      params.targetAccountId
    )
    positionIds = [
      ...new Set(
        positions
          .filter((p) => p.id != null)
          .map((p) => String(p.id))
      ),
    ]
  } catch (err) {
    positionDepsFailed = true
    acquisitionErrors.push(
      `position_deps:${err instanceof Error ? err.message.slice(0, 120) : "failed"}`
    )
    logTradovateSync("sync_error", {
      userId: params.userId,
      connectionId: params.connectionId,
      mappingId: params.mappingId,
      trigger: params.trigger,
      failureCategory: "provider_api_failure",
      failureStage: "unknown",
      errorCode: "position_deps_failed",
      detail: acquisitionErrors[0]?.slice(0, 200),
    })
  }

  const fillPositionIds = positionIdsFromAccountFills(params.accountFills)
  const allPositionIds = [...new Set([...positionIds, ...fillPositionIds])]

  let pairsFromLdeps: NormalizedTradovateFillPair[] = []
  if (allPositionIds.length > 0) {
    const ldeps = await fetchTradovateFillPairsByPositionIdsLdeps(
      supabase,
      params.userId,
      params.connectionId,
      allPositionIds
    )
    pairsFromLdeps = normalizeFillPairRows(ldeps.pairs)
    fillPairLdepsBatchErrors = ldeps.batchErrors.length
    for (const batchErr of ldeps.batchErrors) {
      acquisitionErrors.push(`fill_pair_ldeps:${batchErr}`)
    }
  }

  let pairsFromList: NormalizedTradovateFillPair[] = []
  try {
    const listRows = await fetchTradovateFillPairList(
      supabase,
      params.userId,
      params.connectionId
    )
    pairsFromList = normalizeFillPairRows(listRows)
  } catch (err) {
    acquisitionErrors.push(
      `fill_pair_list:${err instanceof Error ? err.message.slice(0, 120) : "failed"}`
    )
  }

  const merged = mergeAccountScopedTradovateFillPairs({
    primaryFromLdeps: pairsFromLdeps,
    supplementalFromList: pairsFromList,
  })

  const fillIds = new Set(
    params.accountFills.map((f) => String(f.id)).filter(Boolean)
  )
  const accountScoped = merged.filter(
    (p) => fillIds.has(p.buyFillId) || fillIds.has(p.sellFillId)
  )

  const insufficientData =
    accountScoped.length === 0 &&
    (positionDepsFailed ||
      fillPairLdepsBatchErrors > 0 ||
      allPositionIds.length === 0)

  return {
    fillPairs: completedTradovateFillPairs(accountScoped),
    insufficientData,
    acquisitionErrors,
  }
}
