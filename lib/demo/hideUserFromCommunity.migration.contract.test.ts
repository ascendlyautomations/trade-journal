import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"

const sql = readFileSync(
  new URL("../../supabase/migrations/20261004174000_hide_user_from_community_enforcement.sql", import.meta.url),
  "utf8"
)

test("hide from community is its own flag and only admins can change it", () => {
  assert.match(sql, /add column if not exists is_hidden_from_community boolean not null default false/)
  assert.match(sql, /revoke select \(is_hidden_from_community\) on table public\.profiles from anon, authenticated/)
  assert.match(sql, /if new\.is_hidden_from_community is distinct from old\.is_hidden_from_community then/)
  assert.match(sql, /raise exception 'Protected profile fields cannot be modified\.'/)
  assert.doesNotMatch(sql, /update public\.profiles set is_hidden_from_community/i)
  assert.doesNotMatch(sql, /demo\.|guest mode|showcase/i)
})

test("community reads share one visibility helper", () => {
  assert.match(sql, /create or replace function public\.profile_is_visible_to_viewer\(p_profile_id uuid\)/)
  assert.match(sql, /p\.id is not distinct from auth\.uid\(\)/)
  assert.match(sql, /coalesce\(p\.is_hidden_from_community, false\) = false/)
  assert.match(sql, /from public\.admin_users au/)
  assert.match(sql, /create policy profiles_select_hide_from_community/)
  assert.match(sql, /as restrictive/)
  assert.match(sql, /if not public\.profile_is_visible_to_viewer\(v\.id\) then/)
  assert.match(sql, /profile_viewer_can_view_trades/)
  assert.match(sql, /public\.profile_is_visible_to_viewer\(pr\.id\)/)
  assert.match(sql, /public\.profile_is_visible_to_viewer\(p\.id\)/)
})

test("admin directory still returns hidden accounts and does not filter them out", () => {
  assert.match(sql, /is_hidden_from_community boolean/)
  assert.match(sql, /coalesce\(p\.is_hidden_from_community, false\) as is_hidden_from_community/)
  assert.doesNotMatch(sql, /where[\s\S]{0,200}is_hidden_from_community = false/)
  assert.match(sql, /Includes accounts hidden from the community/)
})

test("hiding a user does not delete community rows", () => {
  assert.doesNotMatch(sql, /delete from/i)
  assert.match(sql, /drop policy if exists messages_hide_from_community on public\.messages/)
  assert.doesNotMatch(sql, /create policy messages_hide_from_community/)
})
