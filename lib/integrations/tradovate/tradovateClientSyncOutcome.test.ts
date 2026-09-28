import assert from "node:assert/strict"
import test from "node:test"
import {
  tradovateClientSyncErrorForIncompletePartial,
  tradovateClientSyncOk,
} from "./tradovateClientSyncOutcome.ts"

test("tradovateClientSyncOk rejects partial with zero fills", () => {
  assert.equal(
    tradovateClientSyncOk({
      acquisitionStatus: "IMPORT_SUCCESS_PARTIAL",
      fetchedFillCount: 0,
    }),
    false
  )
  assert.equal(
    tradovateClientSyncOk({
      acquisitionStatus: "IMPORT_SUCCESS_PARTIAL",
      fetchedFillCount: 3,
    }),
    true
  )
  assert.equal(
    tradovateClientSyncOk({
      acquisitionStatus: "IMPORT_SUCCESS_COMPLETE",
      fetchedFillCount: 0,
    }),
    true
  )
})

test("tradovateClientSyncErrorForIncompletePartial", () => {
  assert.equal(
    tradovateClientSyncErrorForIncompletePartial({
      acquisitionStatus: "IMPORT_SUCCESS_PARTIAL",
      fetchedFillCount: 0,
      ledgerExecutionCountAtStart: 0,
    })?.errorCode,
    "import_incomplete_no_fills"
  )
})
