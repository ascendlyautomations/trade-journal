import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20261005041744_trades_list_v2_owner_security_definer.sql"
)

describe("trades list v2 owner security definer migration", () => {
  const sql = fs.readFileSync(migrationPath, "utf8")

  it("restores security definer and a locked search_path on the owner list RPC", () => {
    assert.match(
      sql,
      /alter function public\.rpc_v1_trades_list_bootstrap_v2\([\s\S]*\) security definer/i
    )
    assert.match(sql, /set search_path = public, pg_temp/)
  })

  it("does not restore authenticated table select on public.trades", () => {
    assert.doesNotMatch(sql, /grant select on (table )?public\.trades/i)
    assert.doesNotMatch(sql, /\nsecurity invoker/i)
  })

  it("keeps execute limited to authenticated", () => {
    const revokeAnon = fs.readFileSync(
      path.join(
        process.cwd(),
        "supabase/migrations/20261005041900_trades_list_v2_revoke_anon_execute.sql"
      ),
      "utf8"
    )
    assert.match(sql, /revoke all on function public\.rpc_v1_trades_list_bootstrap_v2/i)
    assert.match(
      sql,
      /grant execute on function public\.rpc_v1_trades_list_bootstrap_v2[\s\S]*to authenticated/i
    )
    assert.match(revokeAnon, /revoke all on function public\.rpc_v1_trades_list_bootstrap_v2[\s\S]*from anon/i)
    assert.doesNotMatch(sql, /grant execute[\s\S]*to anon/i)
  })
})
