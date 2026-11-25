import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { describe, it } from "node:test"

const sql = readFileSync(
  "supabase/migrations/20261124170000_traxpro_trade_ai_server_enforcement.sql",
  "utf8"
)

describe("traxpro trade ai server enforcement migration", () => {
  it("extends assert helper with ai_analyst token", () => {
    assert.match(sql, /TRAXPRO_AI_ANALYST_REQUIRED/)
    assert.match(sql, /'AI_ANALYST', 'AIANALYST', 'TRADE_AI', 'TRADEAI'/)
  })

  it("gates trades.ai_feedback and optionally trade_ai_messages when table exists", () => {
    assert.match(sql, /trades_enforce_ai_feedback_traxpro/)
    assert.match(sql, /column_name = 'ai_feedback'/)
    assert.match(sql, /to_regclass\('public\.trade_ai_messages'\)/)
    assert.doesNotMatch(
      sql,
      /^create trigger trade_ai_messages_enforce_traxpro/m
    )
  })
})