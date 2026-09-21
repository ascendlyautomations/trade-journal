import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20260925120000_trade_public_daily_stats_profile_analytics_v2.sql"
)

describe("Phase 7B migration contract", () => {
  it("defines public profile analytical foundation without client cutover", () => {
    const sql = fs.readFileSync(migrationPath, "utf8")

    assert.match(sql, /trade_public_daily_stats/)
    assert.match(sql, /profile_public_analytics_state/)
    assert.match(sql, /analytics_sync_trade_public_daily_stats_from_row/)
    assert.match(sql, /analytics_trade_row_affects_public_stats/)
    assert.match(sql, /rpc_v1_profile_public_analytics_revision/)
    assert.match(sql, /rpc_v1_profile_analytics_bootstrap_v2/)
    assert.match(sql, /profile_analytics_v2_shadow_compare/)
    assert.match(sql, /backfill_trade_public_daily_stats_batch/)
    assert.match(sql, /rebuild_trade_public_daily_stats_for_user/)

    assert.match(sql, /alter table public\.trade_public_daily_stats enable row level security/)
    assert.match(sql, /alter table public\.profile_public_analytics_state enable row level security/)
    assert.match(sql, /revoke all on table public\.trade_public_daily_stats from public, anon, authenticated/)
    assert.match(sql, /revoke all on table public\.profile_public_analytics_state from public, anon, authenticated/)

    assert.match(sql, /grant execute on function public\.rpc_v1_profile_public_analytics_revision\(uuid\) to authenticated/)
    assert.match(sql, /grant execute on function public\.rpc_v1_profile_public_analytics_revision\(uuid\) to anon/)
    assert.match(sql, /grant execute on function public\.rpc_v1_profile_analytics_bootstrap_v2\(uuid\) to authenticated/)
    assert.match(sql, /grant execute on function public\.rpc_v1_profile_analytics_bootstrap_v2\(uuid\) to anon/)

    assert.match(sql, /revoke all on function public\.profile_analytics_v2_shadow_compare\(uuid, uuid\) from public, anon, authenticated/)
    assert.match(sql, /grant execute on function public\.profile_analytics_v2_shadow_compare\(uuid, uuid\) to service_role/)

    assert.match(sql, /coalesce\(p_trade\.is_public, false\) = true/)
    assert.match(sql, /analytics_bump_profile_public_revision/)
    assert.doesNotMatch(sql, /user_analytics_state.*profile_public/)
    assert.doesNotMatch(sql, /publication.*trade_public_daily_stats/)
    assert.doesNotMatch(sql, /supabase_realtime.*trade_public_daily_stats/)

    assert.match(sql, /security definer[\s\S]*rpc_v1_profile_public_analytics_revision/)
    assert.match(sql, /security definer[\s\S]*rpc_v1_profile_analytics_bootstrap_v2/)

    assert.match(sql, /profile_viewer_can_view_trades/)
    assert.match(sql, /profile_public_daily_stats_mode_rollup/)
    assert.match(sql, /profile_public_daily_stats_raw_parity/)

    assert.match(sql, /trades_maintain_trade_daily_stats\(\)/)
    assert.match(sql, /analytics_trade_eligible_public_profile/)
  })

  it("bumps public revision only from public-affecting trade mutations", () => {
    const sql = fs.readFileSync(migrationPath, "utf8")
    assert.match(sql, /v_bump_public := coalesce\(new\.is_public, false\)/)
    assert.match(sql, /analytics_trade_row_affects_public_stats\(old, new\)/)
    assert.match(sql, /perform public\.analytics_bump_profile_public_revision\(v_user_id\)/)
  })

  it("preserves V1 profile statistics RPC (no replacement in this migration)", () => {
    const sql = fs.readFileSync(migrationPath, "utf8")
    assert.doesNotMatch(sql, /create or replace function public\.rpc_v1_profile_statistics_bootstrap/)
  })
})
