import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { proLimitKindFromError } from "../proGateReason.ts"

describe("proLimitFromError", () => {
  it("maps legacy postgres tokens", () => {
    assert.equal(
      proLimitKindFromError({ message: "FREE_PLAN_DAILY_POST_LIMIT" }),
      "daily_posts"
    )
    assert.equal(
      proLimitKindFromError({
        code: "PRO_LIMIT_REACHED",
        limit: "daily_clips",
      }),
      "daily_clips"
    )
  })

  it("ignores unrelated errors", () => {
    assert.equal(proLimitKindFromError({ message: "JWT expired" }), null)
  })
})
