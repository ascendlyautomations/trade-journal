import assert from "node:assert/strict"
import test from "node:test"
import {
  deriveTradovateClientSyncResult,
  tradovateClientSyncOk,
} from "./tradovateClientSyncOutcome.ts"

const healthyStats = {
  orderDepsFailed: false,
  fillListFailed: false,
  fillLdepsBatchErrors: 0,
}

test("healthy empty ledger → no_available_trade_history, ok", () => {
  const result = deriveTradovateClientSyncResult({
    acquisitionStatus: "IMPORT_SUCCESS_COMPLETE",
    stats: healthyStats,
    acquisitionErrors: [],
    fetchedFillCount: 0,
    ledgerExecutionCountAtStart: 0,
    newExecutions: 0,
    importPreviewTradeCount: 0,
  })
  assert.equal(result.ok, true)
  assert.equal(result.syncOutcome, "no_available_trade_history")
  assert.equal(result.errorCode, "broker_no_available_trade_history")
})

test("healthy existing ledger, zero fills → up_to_date", () => {
  const result = deriveTradovateClientSyncResult({
    acquisitionStatus: "IMPORT_SUCCESS_COMPLETE",
    stats: healthyStats,
    acquisitionErrors: [],
    fetchedFillCount: 0,
    ledgerExecutionCountAtStart: 12,
    newExecutions: 0,
    importPreviewTradeCount: 0,
  })
  assert.equal(result.ok, true)
  assert.equal(result.syncOutcome, "up_to_date")
})

test("fills found → trades_found", () => {
  const result = deriveTradovateClientSyncResult({
    acquisitionStatus: "IMPORT_SUCCESS_COMPLETE",
    stats: healthyStats,
    acquisitionErrors: [],
    fetchedFillCount: 3,
    ledgerExecutionCountAtStart: 0,
    newExecutions: 3,
    importPreviewTradeCount: 1,
  })
  assert.equal(result.syncOutcome, "trades_found")
})

test("provider failure: order deps failed with zero fills", () => {
  const result = deriveTradovateClientSyncResult({
    acquisitionStatus: "IMPORT_FAILED",
    stats: { ...healthyStats, orderDepsFailed: true },
    acquisitionErrors: ["order_deps:unauthorized"],
    fetchedFillCount: 0,
    ledgerExecutionCountAtStart: 0,
    newExecutions: 0,
    importPreviewTradeCount: 0,
  })
  assert.equal(result.ok, false)
  assert.equal(result.syncOutcome, "provider_failure")
})

test("legacy tradovateClientSyncOk wrapper", () => {
  assert.equal(
    tradovateClientSyncOk({
      acquisitionStatus: "IMPORT_SUCCESS_COMPLETE",
      fetchedFillCount: 0,
      ledgerExecutionCountAtStart: 33,
      historicalBackfillComplete: true,
      stats: healthyStats,
      acquisitionErrors: [],
    }),
    true
  )
})
