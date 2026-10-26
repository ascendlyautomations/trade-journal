import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20261026120000_phase1_security_followup.sql"
)

describe("phase 1 security follow-up migration", () => {
  const sql = fs.readFileSync(migrationPath, "utf8")

  it("tracks owner kick separately from voluntary leave", () => {
    assert.match(sql, /owner_removed_at/)
    assert.match(sql, /room_members_mark_owner_removal/)
    assert.match(sql, /owner_removed_rejoin_blocked/)
  })

  it("invalidates join requests when a ban is inserted", () => {
    assert.match(sql, /room_bans_invalidate_join_requests/)
    assert.match(sql, /status in \('pending', 'approved'\)/)
  })

  it("restores legacy iOS private slug SELECT without profile-wide private listing", () => {
    assert.match(sql, /rooms_select_invite/)
    assert.match(sql, /coalesce\(is_private, false\) = true/)
    assert.match(sql, /coalesce\(room_kind, 'community'\) = 'community'/)
  })
})
