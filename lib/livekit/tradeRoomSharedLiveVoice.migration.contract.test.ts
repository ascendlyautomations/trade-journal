import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20261105190000_trade_room_shared_live_voice.sql"
)

describe("Trade Room shared live voice migration", () => {
  const sql = fs.readFileSync(migrationPath, "utf8")

  it("adds rooms.live_voice_kind and resets section voice rows", () => {
    assert.match(sql, /rooms\.live_voice_kind/)
    assert.match(sql, /voice_open/)
    assert.match(sql, /update public\.room_sections/)
    assert.match(sql, /set live_kind = 'text'/)
  })
})
