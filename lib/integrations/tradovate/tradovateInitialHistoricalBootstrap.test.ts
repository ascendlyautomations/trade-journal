import assert from "node:assert/strict"
import test from "node:test"
import {
  collectFillIdsFromCashBalanceLogs,
  filterCashBalanceLogsWithinLookback,
} from "./tradovateCashBalanceLogModels.ts"
import { assessTradovateHistoricalCompleteness } from "./tradovateHistoricalAcquisitionCore.ts"
import { deriveTradovateClientSyncResult } from "./tradovateClientSyncOutcome.ts"

test("collectFillIdsFromCashBalanceLogs ignores null and zero fillId", () => {
  const ids = collectFillIdsFromCashBalanceLogs([
    { fillId: 660290950341 },
    { fillId: null },
    { fillId: 0 },
    { fillId: "660290950347" },
  ])
  assert.deepEqual(ids.sort(), ["660290950341", "660290950347"])
})

test("filterCashBalanceLogsWithinLookback drops old rows", () => {
  const kept = filterCashBalanceLogsWithinLookback(
    [
      { timestamp: "2026-09-15T00:00:00.000Z", fillId: 1 },
      { timestamp: "2020-01-01T00:00:00.000Z", fillId: 2 },
    ],
    "2026-01-01T00:00:00.000Z"
  )
  assert.equal(kept.length, 1)
  assert.equal(kept[0]?.fillId, 1)
})

test("empty ledger bootstrap with zero fills and successful HTTP → backfill complete", () => {
  const completeness = assessTradovateHistoricalCompleteness({
    ledger: {
      executionCount: 0,
      earliestExecutedAt: null,
      latestExecutedAt: null,
      fillIds: new Set(),
    },
    accountFills: [],
    incrementalWatermark: null,
    repairAttempted: false,
    repairFillIdsRequested: [],
    repairFillIdsRecovered: [],
    initialBootstrapAttempted: true,
    initialBootstrapFailed: false,
  })
  assert.equal(completeness.holesDetected.length, 0)
  assert.equal(completeness.historicalBackfillAttempted, true)
  assert.equal(completeness.historicalBackfillComplete, true)
})

test("empty ledger bootstrap HTTP failure → incomplete backfill", () => {
  const completeness = assessTradovateHistoricalCompleteness({
    ledger: {
      executionCount: 0,
      earliestExecutedAt: null,
      latestExecutedAt: null,
      fillIds: new Set(),
    },
    accountFills: [],
    incrementalWatermark: null,
    repairAttempted: false,
    repairFillIdsRequested: [],
    repairFillIdsRecovered: [],
    initialBootstrapAttempted: true,
    initialBootstrapFailed: true,
  })
  assert.equal(completeness.historicalBackfillComplete, false)
})

test("client outcome: empty ledger healthy zero fills → no_available_trade_history", () => {
  const result = deriveTradovateClientSyncResult({
    acquisitionStatus: "IMPORT_SUCCESS_COMPLETE",
    stats: {
      orderDepsFailed: false,
      fillListFailed: false,
      fillLdepsBatchErrors: 0,
    },
    acquisitionErrors: [],
    fetchedFillCount: 0,
    ledgerExecutionCountAtStart: 0,
    newExecutions: 0,
    importPreviewTradeCount: 0,
  })
  assert.equal(result.ok, true)
  assert.equal(result.syncOutcome, "no_available_trade_history")
})
