import assert from "node:assert/strict"
import fs from "node:fs"
import { describe, it } from "node:test"
import path from "node:path"

const migrationPaths = [
  "supabase/migrations/20260903210000_rpc_v1_trade_detail_owner_comparison.sql",
  "supabase/migrations/20260928143000_trade_detail_owner_comparison_pooler_fix.sql",
  "supabase/migrations/20260928160000_owner_comparison_recent_subquery_alias_fix.sql",
]

describe("owner comparison SQL regression", () => {
  for (const rel of migrationPaths) {
    it(`${rel} does not reference alias s outside recent subquery scope`, () => {
      const file = path.join(process.cwd(), rel)
      if (!fs.existsSync(file)) {
        return
      }
      const sql = fs.readFileSync(file, "utf8")
      const recentBlock = sql.match(
        /select\s+count\(\*\)::int,\s*count\(\*\)\s+filter\s+\(where\s+(\w+)\.pnl\s+>\s+0\)[\s\S]*?\)\s+recent;/i
      )
      if (!recentBlock) {
        return
      }
      assert.match(
        recentBlock[0],
        /filter\s+\(where\s+recent\.pnl\s+>\s+0\)/,
        "outer recent aggregate must use recent.pnl, not s.pnl"
      )
      assert.doesNotMatch(
        recentBlock[0],
        /into v_recent_count[\s\S]*?\)\s+recent;[\s\S]*filter\s+\(where\s+s\.pnl/,
        "found s.pnl in outer scope over recent subquery"
      )
    })
  }
})
