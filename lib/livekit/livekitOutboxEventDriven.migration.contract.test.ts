import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20261105160000_livekit_outbox_event_driven.sql"
)

describe("LiveKit outbox event-driven migration", () => {
  const sql = fs.readFileSync(migrationPath, "utf8")

  it("adds claim columns and should_disconnect guard", () => {
    assert.match(sql, /processing_claimed_at/)
    assert.match(sql, /attempt_count/)
    assert.match(sql, /room_livekit_should_disconnect/)
    assert.match(sql, /room_livekit_claim_outbox/)
  })

  it("dispatches on insert via pg_net and retries via pg_cron", () => {
    assert.match(sql, /pg_net/)
    assert.match(sql, /pg_cron/)
    assert.match(sql, /net\.http_post/)
    assert.match(sql, /room_livekit_outbox_dispatch/)
    assert.match(sql, /livekit-outbox-retry/)
    assert.match(sql, /livekit_outbox_processor_config/)
  })
})
