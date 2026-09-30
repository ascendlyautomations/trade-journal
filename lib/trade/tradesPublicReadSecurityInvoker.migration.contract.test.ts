import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20260930153000_trades_public_read_security_invoker.sql"
)

describe("trades_public_read security invoker migration", () => {
  it("recreates the view as security invoker with profile-gated RLS", () => {
    const sql = fs.readFileSync(migrationPath, "utf8")
    assert.match(sql, /security_invoker\s*=\s*true/)
    assert.match(sql, /create view public\.trades_public_read/)
    assert.match(sql, /create policy "trades_select_public"/)
    assert.match(sql, /coalesce\(p\.is_private, false\) = false/)
    assert.match(sql, /revoke select on table public\.trades from anon/)
    assert.match(sql, /grant select \(/)
    assert.doesNotMatch(sql, /psychology_notes/)
    assert.doesNotMatch(sql, /\bnotes\b/)
  })
})
