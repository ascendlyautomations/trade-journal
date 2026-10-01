import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const root = process.cwd()
const behaviorPath = path.join(
  root,
  "supabase/migrations/20261001070000_profile_columns_blocks_achievements.sql"
)
const grantPath = path.join(
  root,
  "supabase/migrations/20261001073000_profiles_select_public_columns.sql"
)

const privateColumns = [
  "locked_account_id",
  "locked_account_name",
  "locked_account_number",
  "locked_account_size",
  "locked_account_type",
  "stripe_customer_id",
  "stripe_price_id",
  "referral_earnings",
  "billing_interval",
]

describe("profile column, block, and achievement privacy migrations", () => {
  const behavior = fs.readFileSync(behaviorPath, "utf8")
  const grant = fs.readFileSync(grantPath, "utf8")

  it("replaces table SELECT with a public-column grant", () => {
    assert.match(grant, /revoke select on table public\.profiles from anon, authenticated/)
    assert.match(grant, /grant select \(/)
    assert.match(grant, /\busername\b/)
    assert.match(grant, /\bis_private\b/)
    for (const column of privateColumns) {
      assert.equal(grant.includes(column), false, column)
    }
  })

  it("keeps owner private fields and hides blocked profiles", () => {
    assert.match(behavior, /function public\.profile_owner_private_fields\(\)/)
    assert.match(behavior, /p\.id = auth\.uid\(\)/)
    assert.match(behavior, /grant execute on function public\.profile_owner_private_fields\(\) to authenticated/)
    assert.match(behavior, /function public\.profile_reader_row\(p_identifier text\)/)
    assert.match(behavior, /profiles_select_hide_blocked/)
    assert.match(behavior, /not public\.viewer_has_block_with\(id\)/)
  })

  it("applies the block check to public content and private-profile achievements", () => {
    assert.match(behavior, /not public\.viewer_has_block_with\(posts\.user_id\)/)
    assert.match(behavior, /not public\.viewer_has_block_with\(stories\.user_id\)/)
    assert.match(behavior, /not public\.viewer_has_block_with\(reels\.user_id\)/)
    assert.match(behavior, /not public\.viewer_has_block_with\(trades\.user_id\)/)
    assert.match(behavior, /achievements_select_public/)
    assert.match(behavior, /coalesce\(p\.is_private, false\) = false/)
    assert.match(behavior, /f\.follower_id = auth\.uid\(\)/)
  })
})
