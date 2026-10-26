import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { confirmProfileOnboardingPersisted } from "./confirmProfileOnboardingPersisted.ts"

describe("confirmProfileOnboardingPersisted", () => {
  it("rejects when onboarding_completed is not true", async () => {
    const supabase = {
      from: () => ({
        select: () => ({
          eq: () => ({
            maybeSingle: async () => ({
              data: {
                id: "u1",
                username: "alex",
                onboarding_completed: false,
              },
              error: null,
            }),
          }),
        }),
      }),
    } as never

    const result = await confirmProfileOnboardingPersisted(supabase, "u1", "alex")
    assert.equal(result.ok, false)
    if (!result.ok) {
      assert.match(result.message, /Could not save onboarding/)
    }
  })

  it("accepts when username and onboarding flag match", async () => {
    const supabase = {
      from: () => ({
        select: () => ({
          eq: () => ({
            maybeSingle: async () => ({
              data: {
                id: "u1",
                username: "alex",
                onboarding_completed: true,
              },
              error: null,
            }),
          }),
        }),
      }),
    } as never

    const result = await confirmProfileOnboardingPersisted(supabase, "u1", "alex")
    assert.equal(result.ok, true)
  })
})
