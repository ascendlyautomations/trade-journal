import assert from "node:assert/strict"
import { describe, it } from "node:test"
import type { Session } from "@supabase/supabase-js"
import {
  passwordResetStatusFromStoredSession,
  readStoredSupabaseSession,
  shouldApplyDelayedTokenRefresh,
  shouldHydrateFromStoredSession,
  supabaseBrowserAuthStorageKey,
} from "./mobileWebSessionRestore.ts"

const session = {
  access_token: "access",
  refresh_token: "refresh",
  expires_in: 3600,
  token_type: "bearer",
  user: { id: "user-1" },
} as Session

describe("mobile web session restore", () => {
  it("hydrates a stored session when refresh reports no session", () => {
    assert.equal(
      shouldHydrateFromStoredSession({
        eventSessionUserId: null,
        storedSession: session,
      }),
      true
    )
    assert.equal(
      shouldHydrateFromStoredSession({
        eventSessionUserId: null,
        storedSession: null,
      }),
      false
    )
    assert.equal(
      shouldHydrateFromStoredSession({
        eventSessionUserId: "user-1",
        storedSession: session,
      }),
      false
    )
  })

  it("applies TOKEN_REFRESHED only when the UI does not already have that user", () => {
    assert.equal(
      shouldApplyDelayedTokenRefresh({
        currentUserId: null,
        refreshedUserId: "user-1",
      }),
      true
    )
    assert.equal(
      shouldApplyDelayedTokenRefresh({
        currentUserId: "user-1",
        refreshedUserId: "user-1",
      }),
      false
    )
    assert.equal(
      shouldApplyDelayedTokenRefresh({
        currentUserId: "user-1",
        refreshedUserId: null,
      }),
      false
    )
  })

  it("reads a recoverable session without treating an empty store as signed in", () => {
    const key = supabaseBrowserAuthStorageKey("https://abccompany.supabase.co")
    assert.equal(key, "sb-abccompany-auth-token")
    const storage = {
      getItem(lookup: string) {
        return lookup === key ? JSON.stringify(session) : null
      },
    }
    assert.equal(readStoredSupabaseSession(storage, key ?? "")?.user.id, "user-1")
    assert.equal(readStoredSupabaseSession(storage, "missing"), null)
    assert.equal(passwordResetStatusFromStoredSession("user-1"), "ready")
    assert.equal(passwordResetStatusFromStoredSession(null), "invalid")
  })
})
