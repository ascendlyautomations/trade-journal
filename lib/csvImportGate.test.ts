import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  csvImportLimitMessage,
  evaluateCsvImportGate,
  FREE_PLAN_CSV_IMPORT_COOLDOWN_MS,
} from "./csvImportGate.ts"

describe("csvImportGate", () => {
  it("allows Pro users regardless of last import", () => {
    const status = evaluateCsvImportGate({
      is_pro: true,
      last_csv_import_at: new Date().toISOString(),
    })
    assert.equal(status.allowed, true)
  })

  it("allows free users with no prior import", () => {
    const status = evaluateCsvImportGate({
      is_pro: false,
      last_csv_import_at: null,
    })
    assert.equal(status.allowed, true)
  })

  it("blocks free users within the 7-day cooldown", () => {
    const status = evaluateCsvImportGate({
      is_pro: false,
      last_csv_import_at: new Date().toISOString(),
    })
    assert.equal(status.allowed, false)
    if (!status.allowed) {
      assert.ok(status.daysUntilNextImport >= 1)
    }
  })

  it("allows free users after the cooldown elapses", () => {
    const last = new Date(Date.now() - FREE_PLAN_CSV_IMPORT_COOLDOWN_MS - 1000)
    const status = evaluateCsvImportGate({
      is_pro: false,
      last_csv_import_at: last.toISOString(),
    })
    assert.equal(status.allowed, true)
  })

  it("includes days remaining in the limit message", () => {
    const message = csvImportLimitMessage(3)
    assert.match(message, /3 days/)
    assert.match(message, /Upgrade to Pro/)
  })
})
