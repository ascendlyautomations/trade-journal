import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20261026140000_phase2_trading_data_integrity.sql"
)

describe("phase 2 trading data integrity migration", () => {
  const sql = fs.readFileSync(migrationPath, "utf8")

  it("returns the completed payout cycle id from record_account_payout", () => {
    assert.match(sql, /v_completed_cycle_id/)
    assert.match(sql, /return v_completed_cycle_id/)
    assert.doesNotMatch(sql, /return v_new_cycle_id/)
  })

  it("deletes payout achievements only by cycle metadata", () => {
    assert.match(sql, /metadata->>'account_payout_cycle_id' = p_cycle_id::text/)
    assert.doesNotMatch(sql, /value_numeric - v_amount/)
    assert.doesNotMatch(sql, /interval '3 days'/)
  })

  it("adds unique CSV import fingerprint indexes", () => {
    assert.match(sql, /trades_csv_import_dedupe_with_account_idx/)
    assert.match(sql, /trades_csv_import_dedupe_no_account_idx/)
  })
})

describe("phase 2 CSV dedupe preflight", () => {
  it("exports read-only duplicate probes aligned with migration indexes", async () => {
    const { CSV_IMPORT_DEDUPE_PREFLIGHT_QUERIES, csvImportDedupeMigrationBlocked } =
      await import("../csvImportDedupePreflight.ts")
    assert.match(CSV_IMPORT_DEDUPE_PREFLIGHT_QUERIES.withAccount, /account_id IS NOT NULL/)
    assert.match(CSV_IMPORT_DEDUPE_PREFLIGHT_QUERIES.withoutAccount, /account_id IS NULL/)
    assert.equal(csvImportDedupeMigrationBlocked(0, 0), false)
    assert.equal(csvImportDedupeMigrationBlocked(1, 0), true)
  })
})
