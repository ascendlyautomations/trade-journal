import assert from "node:assert/strict"
import test from "node:test"
import {
  BROKER_ACCOUNT_SYNC_STATUSES,
  normalizeBrokerAccountSyncStatus,
} from "./brokerIntegrationSync.ts"

test("normalizeBrokerAccountSyncStatus accepts DB-aligned values", () => {
  for (const status of BROKER_ACCOUNT_SYNC_STATUSES) {
    assert.equal(normalizeBrokerAccountSyncStatus(status), status)
  }
  assert.equal(normalizeBrokerAccountSyncStatus("partial"), "partial")
})

test("normalizeBrokerAccountSyncStatus maps unknown values to error", () => {
  assert.equal(normalizeBrokerAccountSyncStatus("no_new_trades"), "error")
  assert.equal(normalizeBrokerAccountSyncStatus(""), "error")
})
