import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20260921120000_trade_daily_stats_analytical_foundation.sql"
)

describe("Phase 1B migration contract", () => {
  it("defines shadow infrastructure without wiring production RPCs", () => {
    const sql = fs.readFileSync(migrationPath, "utf8")
    assert.match(sql, /analytics_calendar_day/)
    assert.match(sql, /analytics_legacy_trading_day_key/)
    assert.match(sql, /trade_daily_stats/)
    assert.match(sql, /user_analytics_state/)
    assert.match(sql, /rpc_v1_analytics_daily_range_bootstrap/)
    assert.match(sql, /rpc_v1_analytics_shadow_compare_range/)
    const calendarV2Path = path.join(
      process.cwd(),
      "supabase/migrations/20260923120000_analytics_calendar_v2_day_trades_rpc.sql"
    )
    const calendarV2 = fs.readFileSync(calendarV2Path, "utf8")
    assert.match(calendarV2, /rpc_v1_analytics_calendar_day_trades/)

    const dashboardV3 = fs.readFileSync(
      path.join(
        process.cwd(),
        "supabase/migrations/20260924120000_analytics_dashboard_v3_bootstrap.sql"
      ),
      "utf8"
    )
    assert.match(dashboardV3, /rpc_v1_analytics_dashboard_bootstrap_v3/)
    assert.match(dashboardV3, /grant execute on function public\.rpc_v1_analytics_dashboard_bootstrap_v3/)
    const dashboardV3Fix = fs.readFileSync(
      path.join(
        process.cwd(),
        "supabase/migrations/20260924150000_analytics_dashboard_v3_payload_fix.sql"
      ),
      "utf8"
    )
    assert.match(dashboardV3Fix, /account_preset_metrics/)
    assert.match(dashboardV3Fix, /rpc_v1_analytics_dashboard_account_charts_v3/)

    const revisionRpc = fs.readFileSync(
      path.join(
        process.cwd(),
        "supabase/migrations/20260924170000_rpc_v1_analytics_revision.sql"
      ),
      "utf8"
    )
    assert.match(revisionRpc, /rpc_v1_analytics_revision/)
    assert.match(revisionRpc, /security invoker/)
    assert.match(revisionRpc, /grant execute on function public\.rpc_v1_analytics_revision/)

    const tradesListCastFix = fs.readFileSync(
      path.join(
        process.cwd(),
        "supabase/migrations/20260921203000_fix_rpc_v1_trades_list_bootstrap_entry_time_text_cast.sql"
      ),
      "utf8"
    )
    assert.match(tradesListCastFix, /analytics_wire_trade_timestamp_utc/)
    assert.match(tradesListCastFix, /rpc_v1_trades_list_bootstrap/)
    assert.match(calendarV2, /analytics_calendar_day\(\s*\n?\s*t\.entry_time,\s*\n?\s*t\.exit_time,\s*\n?\s*t\.created_at/)
    const calendarV2Fix = fs.readFileSync(
      path.join(
        process.cwd(),
        "supabase/migrations/20260923140000_analytics_calendar_day_trades_phase2_signature_fix.sql"
      ),
      "utf8"
    )
    assert.match(calendarV2Fix, /analytics_realized_sort_ts/)
    assert.match(sql, /revoke all on function public.rebuild_trade_daily_stats_for_user\(uuid\) from public, anon, authenticated/)
    assert.doesNotMatch(sql, /rpc_v1_dashboard_bootstrap/)
    assert.doesNotMatch(sql, /rpc_v1_calendar_bootstrap/)
    assert.match(sql, /nulls not distinct/i)
    assert.match(sql, /trades_maintain_trade_daily_stats_trg/)
  })
})
