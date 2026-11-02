import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { profilePath, signedInProfileHref } from "./profileRoutes.ts"

describe("signedInProfileHref", () => {
  it("prefers username when the session profile is ready", () => {
    assert.equal(
      signedInProfileHref({ username: "john_trades", id: "abc" }, "abc"),
      "/profile/john_trades"
    )
  })

  it("falls back to the signed-in user id instead of bare /profile", () => {
    assert.equal(signedInProfileHref(null, "user-1"), "/profile/user-1")
    assert.equal(profilePath({ id: "user-1" }), "/profile/user-1")
  })

  it("uses /profile only when no viewer is known, so the index page can redirect", () => {
    assert.equal(signedInProfileHref(null, null), "/profile")
  })
})
