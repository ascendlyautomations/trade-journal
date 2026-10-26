import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20261026170000_phase3_room_ban_atomic.sql"
)

describe("phase 3 reliability migration", () => {
  const sql = fs.readFileSync(migrationPath, "utf8")

  it("defines atomic room ban RPC with moderation guard", () => {
    assert.match(sql, /rpc_v1_ban_trade_room_member/)
    assert.match(sql, /can_moderate_room_member_target/)
    assert.match(sql, /insert into public\.room_bans/)
    assert.match(sql, /update public\.room_members/)
  })
})
