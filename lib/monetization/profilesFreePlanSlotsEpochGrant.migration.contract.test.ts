import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const transitionsPath = path.join(
  process.cwd(),
  "supabase/migrations/20261103150000_traxpro_free_account_slot_transitions.sql"
)
const grantPath = path.join(
  process.cwd(),
  "supabase/migrations/20261103160000_profiles_grant_free_plan_trade_slots_epoch.sql"
)
const baseGrantPath = path.join(
  process.cwd(),
  "supabase/migrations/20261001073000_profiles_select_public_columns.sql"
)

describe("profiles free-plan slot epoch column grants", () => {
  it("adds epoch columns on profiles without table-wide SELECT", () => {
    const transitions = fs.readFileSync(transitionsPath, "utf8")
    assert.match(transitions, /free_plan_trade_slots_epoch/)
    assert.match(transitions, /free_plan_trade_slots_confirmed_epoch/)
    assert.doesNotMatch(
      transitions,
      /grant select on table public\.profiles to anon, authenticated/
    )

    const grant = fs.readFileSync(grantPath, "utf8")
    assert.match(grant, /grant select \(/)
    assert.match(grant, /free_plan_trade_slots_epoch/)
    assert.match(grant, /free_plan_trade_slots_confirmed_epoch/)
    assert.match(grant, /to anon, authenticated/)
  })

  it("base profiles grant remains column-scoped (regression for 42501)", () => {
    const base = fs.readFileSync(baseGrantPath, "utf8")
    assert.match(base, /revoke select on table public\.profiles from anon, authenticated/)
    assert.doesNotMatch(base, /free_plan_trade_slots_epoch/)
  })
})
