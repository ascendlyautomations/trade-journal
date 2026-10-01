import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20261001060000_room_join_and_remove_follower_privacy.sql"
)

describe("room join and remove-follower privacy migration", () => {
  const sql = fs.readFileSync(migrationPath, "utf8")

  it("drops legacy self-join policies and qualifies the approval room id", () => {
    assert.match(sql, /drop policy if exists "Users can join rooms"/)
    assert.match(sql, /drop policy if exists "Users can rejoin rooms"/)
    assert.match(sql, /jr\.room_id = room_members\.room_id/)
    assert.doesNotMatch(sql, /jr\.room_id = jr\.room_id/)
    assert.match(sql, /coalesce\(r\.join_policy, 'open'\) = 'open'/)
  })

  it("blocks approval-room rejoin and lets the followee delete the edge", () => {
    assert.match(sql, /room_join_not_allowed/)
    assert.match(sql, /following_id = auth\.uid\(\)/)
    assert.match(sql, /followers_delete_by_followee/)
  })
})
