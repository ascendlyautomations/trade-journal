import assert from "node:assert/strict"
import test from "node:test"
import {
  collectFillIdsFromCashBalanceLogs,
  filterCashBalanceLogsWithinLookback,
} from "./tradovateCashBalanceLogModels.ts"
import { assessTradovateHistoricalCompleteness } from "./tradovateHistoricalAcquisitionCore.ts"
import {
  tradovateClientSyncErrorForIncompletePartial,
  tradovateClientSyncOk,
} from "./tradovateClientSyncOutcome.ts"

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

test("empty ledger bootstrap with zero fills → incomplete history, no MGC holes", () => {
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
  })
  assert.equal(completeness.holesDetected.length, 0)
  assert.equal(completeness.historicalBackfillAttempted, true)
  assert.equal(completeness.historicalBackfillComplete, false)
  assert.ok(completeness.requestedStart)
})

test("client outcome: empty ledger incomplete history", () => {
  assert.equal(
    tradovateClientSyncOk({
      acquisitionStatus: "IMPORT_SUCCESS_PARTIAL",
      fetchedFillCount: 0,
      ledgerExecutionCountAtStart: 0,
      historicalBackfillComplete: false,
    }),
    false
  )
  assert.equal(
    tradovateClientSyncErrorForIncompletePartial({
      acquisitionStatus: "IMPORT_SUCCESS_PARTIAL",
      fetchedFillCount: 0,
      ledgerExecutionCountAtStart: 0,
      historicalBackfillComplete: false,
    })?.errorCode,
    "import_incomplete_history"
  )
})

test("client outcome: initialized ledger, complete acquisition, zero new fills → ok", () => {
  assert.equal(
    tradovateClientSyncOk({
      acquisitionStatus: "IMPORT_SUCCESS_COMPLETE",
      fetchedFillCount: 0,
      ledgerExecutionCountAtStart: 33,
      historicalBackfillComplete: true,
    }),
    true
  )
})
