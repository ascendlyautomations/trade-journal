import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20260929221000_trades_public_read_boundary.sql"
)

describe("trades_public_read boundary migration", () => {
  it("drops trades_select_public and defines a journal-safe view", () => {
    const sql = fs.readFileSync(migrationPath, "utf8")
    assert.match(sql, /drop policy if exists "trades_select_public"/)
    assert.match(sql, /create view public\.trades_public_read/)
    assert.match(sql, /coalesce\(is_public, false\) = true/)
    assert.match(sql, /grant select on public\.trades_public_read to anon, authenticated/)
    assert.doesNotMatch(sql, /psychology_notes/)
    assert.doesNotMatch(sql, /\bnotes\b/)
    assert.doesNotMatch(sql, /\bstrategy\b/)
  })
})
