import { describe, it } from "node:test"
import assert from "node:assert/strict"
import {
  evaluateCsvImportGate,
  FREE_PLAN_CSV_IMPORT_PRICING_LABEL,
  assertCsvImportAllowedForFreePlan,
} from "./csvImportGate.ts"

describe("csvImportGate", () => {
  it("always allows CSV import on Free", () => {
    assert.deepEqual(evaluateCsvImportGate(), { allowed: true })
    assert.equal(FREE_PLAN_CSV_IMPORT_PRICING_LABEL, "Unlimited CSV imports")
  })

  it("assertCsvImportAllowedForFreePlan is always ok", async () => {
    const result = await assertCsvImportAllowedForFreePlan(
      {} as never,
      "user-id"
    )
    assert.deepEqual(result, { ok: true })
  })
})
export {}
