import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20261114184649_weekly_trading_report_push_schedule.sql"
)

describe("weekly trading report push migration", () => {
  const sql = fs.readFileSync(migrationPath, "utf8")

  it("selects eligibility with the Eastern calendar day and excludes backtests", () => {
    assert.match(sql, /analytics_calendar_day\(t\.entry_time, t\.exit_time, t\.created_at\)/)
    assert.match(sql, /coalesce\(t\.mode, ''\) <> 'backtest'/)
    assert.match(sql, /jsonb_agg\(distinct t\.user_id\)/)
    assert.doesNotMatch(sql, /entry_time >=/)
  })

  it("schedules Saturday 17:00 UTC and an 18:00 UTC retry via pg_net", () => {
    assert.match(sql, /pg_net/)
    assert.match(sql, /pg_cron/)
    assert.match(sql, /net\.http_get/)
    assert.match(sql, /weekly-trading-report-push/)
    assert.match(sql, /'0 17 \* \* 6'/)
    assert.match(sql, /weekly-trading-report-push-retry/)
    assert.match(sql, /'0 18 \* \* 6'/)
    assert.match(sql, /private\.weekly_report_push_config/)
    assert.doesNotMatch(sql, /bearer_secret\s+text not null default/i)
  })
})
