import assert from "node:assert/strict"
import test from "node:test"
import { tradovateAcquisitionErrorsIndicateAuthFailure } from "./tradovateAcquisitionAuth.ts"
import { resolveTradovateSyncAcquisitionFailure } from "./tradovateSyncAcquisitionFailure.ts"
import { tradovateClientSyncOk } from "./tradovateClientSyncOutcome.ts"

test("order_deps unauthorized is auth failure", () => {
  assert.equal(
    tradovateAcquisitionErrorsIndicateAuthFailure([
      "order_deps:unauthorized:unauthorized",
    ]),
    true
  )
})

test("IMPORT_FAILED with unauthorized resolves reconnect_required", () => {
  const failure = resolveTradovateSyncAcquisitionFailure({
    acquisitionStatus: "IMPORT_FAILED",
    acquisitionErrors: ["order_deps:unauthorized:unauthorized"],
  })
  assert.equal(failure?.status, "reconnect_required")
  assert.equal(failure?.errorCode, "reconnect_required")
})

test("IMPORT_FAILED never client-ok", () => {
  assert.equal(
    tradovateClientSyncOk({
      acquisitionStatus: "IMPORT_FAILED",
      fetchedFillCount: 0,
    }),
    false
  )
})

test("complete acquisition with zero new trades remains client-ok", () => {
  assert.equal(
    tradovateClientSyncOk({
      acquisitionStatus: "IMPORT_SUCCESS_COMPLETE",
      fetchedFillCount: 0,
    }),
    true
  )
})
