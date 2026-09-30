import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20260929220000_conversation_participants_insert_fix.sql"
)

describe("conversation_participants INSERT hardening migration", () => {
  it("removes self-join via user_id = auth.uid() alone", () => {
    const sql = fs.readFileSync(migrationPath, "utf8")
    assert.match(sql, /drop policy if exists "conversation_participants_insert_member"/)
    assert.match(sql, /is_conversation_participant\(conversation_id, auth\.uid\(\)\)/)
    assert.match(sql, /not exists/)
    assert.doesNotMatch(sql, /user_id = auth\.uid\(\)\s*\n\s*or/i)
    assert.doesNotMatch(sql, /with check \(\s*user_id = auth\.uid\(\)/)
  })
})
