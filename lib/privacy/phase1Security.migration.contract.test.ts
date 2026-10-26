import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const migrationPath = path.join(
  process.cwd(),
  "supabase/migrations/20261025180000_phase1_security_accounts_and_rooms.sql"
)

describe("phase 1 security migration", () => {
  const sql = fs.readFileSync(migrationPath, "utf8")

  it("enables owner-only RLS on public.accounts", () => {
    assert.match(sql, /alter table public\.accounts enable row level security/)
    assert.match(sql, /accounts_select_own/)
    assert.match(sql, /user_id = auth\.uid\(\)/)
    assert.match(sql, /accounts_insert_own/)
    assert.match(sql, /accounts_update_own/)
  })

  it("stops enumerating private rooms via profile and slug policies", () => {
    assert.match(sql, /drop policy if exists "rooms_select_profile_public"/)
    assert.match(sql, /coalesce\(is_private, false\) = false/)
    assert.match(sql, /drop policy if exists "rooms_select_invite"/)
    assert.match(sql, /owner_user_id is null/)
  })

  it("blocks open self-join on private rooms and provides invite lookup RPC", () => {
    assert.match(sql, /rpc_v1_trade_room_invite_lookup/)
    assert.match(sql, /coalesce\(r\.is_private, false\) = false/)
    assert.match(sql, /room_members_insert_self/)
    assert.match(sql, /room_members_before_update_guard/)
  })

  it("allows join requests for private rooms and forces approval on create", () => {
    assert.match(sql, /room_join_requests_insert_self/)
    assert.match(sql, /coalesce\(r\.is_private, false\) = true/)
    assert.match(sql, /if coalesce\(p_is_private, false\) then/)
    assert.match(sql, /v_join_policy := 'approval'/)
  })

  it("restricts moderators to lifting only their own bans", () => {
    assert.match(sql, /room_bans_delete_moderator/)
    assert.match(sql, /can_manage_trade_room\(room_id, auth\.uid\(\)\)/)
    assert.match(sql, /banned_by = auth\.uid\(\)/)
  })
})
