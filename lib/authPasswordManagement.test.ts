import assert from "node:assert/strict"
import { describe, it } from "node:test"
import type { User } from "@supabase/supabase-js"
import {
  isGoogleAuthUser,
  profileHasEmailPasswordFlag,
  resolveGooglePasswordUiMode,
} from "./authPasswordManagement.ts"

function mockUser(partial: Partial<User>): User {
  return partial as User
}

describe("authPasswordManagement", () => {
  it("detects Google OAuth users", () => {
    assert.equal(
      isGoogleAuthUser(
        mockUser({ app_metadata: { provider: "google", providers: ["google"] } })
      ),
      true
    )
  })

  it("uses profiles.has_email_password as Google password UI source of truth", () => {
    assert.equal(resolveGooglePasswordUiMode(false), "create")
    assert.equal(resolveGooglePasswordUiMode(null), "create")
    assert.equal(resolveGooglePasswordUiMode(true), "update")
    assert.equal(profileHasEmailPasswordFlag(true), true)
    assert.equal(profileHasEmailPasswordFlag(false), false)
  })
})
