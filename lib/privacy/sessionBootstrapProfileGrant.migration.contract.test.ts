import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"
import { fileURLToPath } from "node:url"

const migrationPath = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  "../../supabase/migrations/20261001172705_session_bootstrap_column_safe_profile_reads.sql"
)

describe("session bootstrap profile column grant fix", () => {
  const sql = fs.readFileSync(migrationPath, "utf8")

  it("keeps session bootstrap invoker and stops passing a whole profiles row", () => {
    assert.match(sql, /rpc_v1_session_bootstrap must stay security invoker/)
    assert.match(sql, /public\._v1_session_is_pro\(p\)/)
    assert.match(sql, /public\._v1_session_early_access_active\(p\)/)
    assert.match(sql, /public\._v1_session_is_pro\(p\.is_pro, p\.creator_access/)
    assert.match(
      sql,
      /public\._v1_session_early_access_active\(p\.early_access_status, p\.early_access_enrolled_at/
    )
    assert.match(sql, /security invoker/)
  })

  it("does not restore table select, disable RLS, or switch to security definer", () => {
    assert.doesNotMatch(sql, /grant select on table public\.profiles/i)
    assert.doesNotMatch(sql, /disable row level security/i)
    assert.doesNotMatch(sql, /alter function public\.rpc_v1_session_bootstrap\(\) security definer/i)
    assert.doesNotMatch(sql, /locked_account_id/)
    assert.doesNotMatch(sql, /referral_earnings/)
    assert.doesNotMatch(sql, /billing_interval/)
    assert.doesNotMatch(sql, /stripe_price_id/)
  })
})
