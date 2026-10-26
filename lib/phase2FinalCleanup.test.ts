import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"
import { fileURLToPath } from "node:url"
import {
  csvImportDedupeMigrationBlocked,
  CSV_IMPORT_DEDUPE_PREFLIGHT_QUERIES,
} from "./csvImportDedupePreflight.ts"

const root = path.dirname(fileURLToPath(import.meta.url))

describe("phase 2 final cleanup regressions", () => {
  describe("user streak analytics load failures", () => {
    const streaksSource = fs.readFileSync(
      path.join(root, "userStreaksCache.ts"),
      "utf8"
    )

    it("does not swallow analytics history errors as empty trades", () => {
      assert.doesNotMatch(
        streaksSource,
        /ensureAnalyticsTradesHistory\([^)]*\)\.catch\(\(\) => \[\]\)/
      )
      assert.match(streaksSource, /catch \(loadErr\)/)
      assert.match(streaksSource, /streakSnapshotIsMaterialized/)
      assert.match(streaksSource, /invalidated: !preserved/)
    })
  })

  describe("copy trading post-insert confirmation", () => {
    const copySource = fs.readFileSync(path.join(root, "tradeCopyTrading.ts"), "utf8")

    it("surfaces owner read failures and rejects partial batch confirmation", () => {
      assert.match(copySource, /if \(owned\.error\)/)
      assert.match(copySource, /insertedIDs\.length !== rows\.length/)
      assert.match(copySource, /owned\.rows\.length !== insertedIDs\.length/)
      assert.doesNotMatch(
        copySource,
        /owned\.rows\.length > 0 \? owned\.rows : insertedIDs\.map/
      )
    })
  })

  describe("CSV dedupe migration preflight", () => {
    it("documents duplicate probes for both index shapes", () => {
      assert.match(
        CSV_IMPORT_DEDUPE_PREFLIGHT_QUERIES.withAccount,
        /import_fingerprint/
      )
      assert.match(
        CSV_IMPORT_DEDUPE_PREFLIGHT_QUERIES.withoutAccount,
        /account_id IS NULL/
      )
      assert.match(
        CSV_IMPORT_DEDUPE_PREFLIGHT_QUERIES.withAccount,
        /HAVING count\(\*\) > 1/
      )
    })

    it("blocks migration when duplicate fingerprint groups exist", () => {
      assert.equal(csvImportDedupeMigrationBlocked(0, 0), false)
      assert.equal(csvImportDedupeMigrationBlocked(1, 0), true)
      assert.equal(csvImportDedupeMigrationBlocked(0, 2), true)
    })

    it("migration contract references the same fingerprint columns", () => {
      const migration = fs.readFileSync(
        path.join(
          root,
          "../supabase/migrations/20261026140000_phase2_trading_data_integrity.sql"
        ),
        "utf8"
      )
      assert.match(migration, /import_fingerprint/)
      for (const query of Object.values(CSV_IMPORT_DEDUPE_PREFLIGHT_QUERIES)) {
        assert.match(query, /public\.trades/)
      }
    })
  })

  describe("rich trade enrichment source contract", () => {
    it("propagates rpcTradesOwnerRows errors in ensureRichTradeRowsByIds", () => {
      const source = fs.readFileSync(path.join(root, "appDataCache.ts"), "utf8")
      assert.match(source, /if \(error\) \{\s*throw error\s*\}/)
    })
  })
})
