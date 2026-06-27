import { describe, expect, it } from "vitest"
import type { User } from "@supabase/supabase-js"
import {
  getPasswordManagementMode,
  isGoogleAuthUser,
  userHasEmailPasswordIdentity,
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
    expect(
      isGoogleAuthUser(mockUser({ identities: [{ provider: "google" } as never] }))
    ).toBe(true)
  })

  it("detects email/password identity", () => {
    expect(
      userHasEmailPasswordIdentity(
        mockUser({ app_metadata: { provider: "email", providers: ["email"] } })
      )
    ).toBe(true)
    expect(
      userHasEmailPasswordIdentity(
        mockUser({
          app_metadata: { provider: "google", providers: ["google", "email"] },
        })
      )
    ).toBe(true)
  })

  it("uses create mode for Google-only accounts", () => {
    expect(
      getPasswordManagementMode(
        mockUser({ app_metadata: { provider: "google", providers: ["google"] } })
      )
    ).toBe("create")
  })

  it("uses change mode for email accounts and Google accounts with a password", () => {
    expect(
      getPasswordManagementMode(
        mockUser({ app_metadata: { provider: "email", providers: ["email"] } })
      )
    ).toBe("change")

    expect(
      getPasswordManagementMode(
        mockUser({
          app_metadata: { provider: "google", providers: ["google", "email"] },
        })
      )
    ).toBe("change")
  })
})
