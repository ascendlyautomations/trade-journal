import type { SupabaseClient } from "@supabase/supabase-js"
import {
  listLinkedTradovateImportTargets,
  runTradovateManualImportBatch,
  type LinkedTradovateImportTarget,
} from "@/lib/integrations/tradovate/runTradovateManualImportBatch"
import {
  listLinkedRithmicImportTargets,
  runRithmicManualImportBatch,
  type LinkedRithmicImportTarget,
} from "@/lib/integrations/rithmic/runRithmicManualImportBatch"

export type LinkedBrokerImportTarget =
  | (LinkedTradovateImportTarget & { provider: "tradovate" })
  | LinkedRithmicImportTarget

export type BrokerManualImportBatchResult = {
  ok: boolean
  results: {
    provider: "tradovate" | "rithmic"
    mappingId: string
    connectionId: string
    ok: boolean
    newTradeIds: string[]
    tradesCreated: number
    tradesUpdated: number
    newExecutions: number
    duplicateExecutions: number
    error?: string
  }[]
  newTradeIds: string[]
  totalTradesCreated: number
  totalTradesUpdated: number
}

export async function listLinkedBrokerImportTargets(
  supabase: SupabaseClient,
  userId: string
): Promise<LinkedBrokerImportTarget[]> {
  const [tradovate, rithmic] = await Promise.all([
    listLinkedTradovateImportTargets(supabase, userId),
    listLinkedRithmicImportTargets(supabase, userId),
  ])
  return [
    ...tradovate.map((t) => ({ ...t, provider: "tradovate" as const })),
    ...rithmic,
  ]
}

export async function runBrokerManualImportBatch(
  supabase: SupabaseClient,
  userId: string,
  targets: LinkedBrokerImportTarget[]
): Promise<BrokerManualImportBatchResult> {
  const tradovateTargets = targets.filter(
    (t): t is LinkedTradovateImportTarget & { provider: "tradovate" } =>
      t.provider === "tradovate"
  )
  const rithmicTargets = targets.filter(
    (t): t is LinkedRithmicImportTarget => t.provider === "rithmic"
  )

  const [tradovateBatch, rithmicBatch] = await Promise.all([
    tradovateTargets.length > 0
      ? runTradovateManualImportBatch(supabase, userId, tradovateTargets)
      : Promise.resolve({
          ok: true,
          results: [],
          newTradeIds: [] as string[],
          totalTradesCreated: 0,
          totalTradesUpdated: 0,
        }),
    rithmicTargets.length > 0
      ? runRithmicManualImportBatch(supabase, userId, rithmicTargets)
      : Promise.resolve({
          ok: true,
          results: [],
          newTradeIds: [] as string[],
          totalTradesCreated: 0,
          totalTradesUpdated: 0,
        }),
  ])

  const results = [
    ...tradovateBatch.results.map((r) => ({
      provider: "tradovate" as const,
      mappingId: r.mappingId,
      connectionId: r.connectionId,
      ok: r.ok,
      newTradeIds: r.newTradeIds,
      tradesCreated: r.tradesCreated,
      tradesUpdated: r.tradesUpdated,
      newExecutions: r.newExecutions,
      duplicateExecutions: r.duplicateExecutions,
      error: r.error,
    })),
    ...rithmicBatch.results,
  ]

  const newTradeIds = [...new Set([...tradovateBatch.newTradeIds, ...rithmicBatch.newTradeIds])]

  return {
    ok: tradovateBatch.ok && rithmicBatch.ok,
    results,
    newTradeIds,
    totalTradesCreated:
      tradovateBatch.totalTradesCreated + rithmicBatch.totalTradesCreated,
    totalTradesUpdated:
      tradovateBatch.totalTradesUpdated + rithmicBatch.totalTradesUpdated,
  }
}
