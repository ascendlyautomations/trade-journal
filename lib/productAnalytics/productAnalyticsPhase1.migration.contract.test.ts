import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

describe("product analytics phase 1 migration", () => {
  it("defines ingest RPC and rollup tables", () => {
    const root = process.cwd()
    const sql = fs.readFileSync(
      path.join(root, "supabase/migrations/20261122230000_product_analytics_phase1.sql"),
      "utf8"
    )
    assert.match(sql, /create table if not exists public\.product_events/)
    assert.match(sql, /rpc_v1_product_events_ingest/)
    assert.match(sql, /product_daily_user_activity/)
    assert.match(sql, /admin_users/)
    assert.match(sql, /product_analytics_purge_raw_events/)
  })

  it("orders function parameters for PostgreSQL (no default before required)", () => {
    const root = process.cwd()
    const sql = fs.readFileSync(
      path.join(root, "supabase/migrations/20261122230000_product_analytics_phase1.sql"),
      "utf8"
    )

    assert.match(
      sql,
      /product_analytics_emit_server_event\s*\([\s\S]*?p_dedupe_key text,\s*\n\s*p_props jsonb default/
    )
    assert.doesNotMatch(
      sql,
      /product_analytics_emit_server_event\s*\([\s\S]*?p_props jsonb default[\s\S]*?p_dedupe_key text/
    )
    assert.match(
      sql,
      /revoke all on function public\.product_analytics_emit_server_event\(uuid, text, text, text, jsonb\)/
    )

    const funcBlocks = [
      ...sql.matchAll(
        /create or replace function public\.(\w+)\(([\s\S]*?)\)\s*returns/gi
      ),
    ]
    for (const [, name, params] of funcBlocks) {
      const lines = params
        .split("\n")
        .map((l) => l.trim())
        .filter((l) => l && !l.startsWith("--"))
      let seenDefault = false
      for (const line of lines) {
        const hasDefault = /\bdefault\b/i.test(line)
        if (hasDefault) seenDefault = true
        else if (seenDefault) {
          assert.fail(
            `${name}: required parameter follows a defaulted parameter (PostgreSQL 42P13): ${line}`
          )
        }
      }
    }
  })
})