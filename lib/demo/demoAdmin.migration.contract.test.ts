import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"

const sql = readFileSync(
  new URL("../../supabase/migrations/20261003023855_demo_admin.sql", import.meta.url),
  "utf8"
)

test("demo admin mutations require admin_users and stay off the visitor RPC", () => {
  assert.match(sql, /from public\.admin_users where user_id = auth\.uid\(\)/)
  assert.match(sql, /grant execute on function public\.rpc_v1_admin_demo\(text, jsonb\) to authenticated/)
  assert.match(sql, /revoke all on function public\.rpc_v1_admin_demo\(text, jsonb\) from public, anon/)
  assert.match(sql, /validate_snapshot\(v_snapshot\)/)
  assert.match(sql, /update publications set is_current = false where is_current/)
  assert.doesNotMatch(sql, /grant select on demo\./i)
  assert.doesNotMatch(sql, /create policy/i)
  assert.match(sql, /restored_from/)
})
