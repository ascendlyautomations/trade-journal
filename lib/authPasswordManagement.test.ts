import { describe, expect, it } from "vitest"
import type { User } from "@supabase/supabase-js"
import {
  isGoogleAuthUser,
  profileHasEmailPasswordFlag,
  resolveGooglePasswordUiMode,
} from "./authPasswordManagement"

function mockUser(partial: Partial<User>): User {
  return partial as User
}

describe("authPasswordManagement", () => {
  it("detects Google OAuth users", () => {
    expect(
      isGoogleAuthUser(
        mockUser({ app_metadata: { provider: "google", providers: ["google"] } })
      )
    ).toBe(true)
  })

  it("uses profiles.has_email_password as Google password UI source of truth", () => {
    expect(resolveGooglePasswordUiMode(false)).toBe("create")
    expect(resolveGooglePasswordUiMode(null)).toBe("create")
    expect(resolveGooglePasswordUiMode(true)).toBe("update")
    expect(profileHasEmailPasswordFlag(true)).toBe(true)
    expect(profileHasEmailPasswordFlag(false)).toBe(false)
  })
})
