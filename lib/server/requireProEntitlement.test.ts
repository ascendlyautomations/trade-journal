import assert from "node:assert/strict"
import { describe, it } from "node:test"
import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "../database.types.ts"
import { isProActive } from "../subscription.ts"
import { readProEntitlementProfile } from "../proEntitlementProfileRead.ts"

function profileClient(
  run: (signal: AbortSignal | undefined) => Promise<{
    data: Record<string, unknown> | null
    error: { message?: string; code?: string } | null
  }>
) {
  let signal: AbortSignal | undefined
  const builder: Record<string, unknown> = {}
  for (const method of ["select", "eq", "single"]) {
    builder[method] = () => builder
  }
  builder.abortSignal = (next: AbortSignal) => {
    signal = next
    return builder
  }
  builder.then = (
    resolve: (value: unknown) => void,
    reject?: (reason: unknown) => void
  ) => run(signal).then(resolve, reject)
  return {
    from() {
      return builder
    },
  } as unknown as SupabaseClient<Database>
}

describe("requireProEntitlement policy (isProActive)", () => {
  it("rejects a typical free profile before AI would run", () => {
    assert.equal(
      isProActive({
        is_pro: false,
        creator_access: false,
        subscription_status: null,
        trial_end: null,
      }),
      false
    )
  })

  it("accepts manual TraxPro via is_pro", () => {
    assert.equal(
      isProActive({
        is_pro: true,
        subscription_status: null,
      }),
      true
    )
  })

  it("accepts active Stripe subscription", () => {
    assert.equal(
      isProActive({
        is_pro: false,
        subscription_status: "active",
      }),
      true
    )
  })
})

describe("readProEntitlementProfile timeout", () => {
  it("returns null when the profile read times out, even if a Pro row is in-flight", async () => {
    const profile = await readProEntitlementProfile(
      profileClient((signal) => {
        return new Promise((resolve) => {
          signal?.addEventListener("abort", () => {
            resolve({
              data: { is_pro: true },
              error: { message: "AbortError: The user aborted a request." },
            })
          })
        })
      }),
      "user-1",
      { timeoutMs: 40 }
    )
    assert.equal(profile, null)
  })

  it("returns the profile when the read succeeds", async () => {
    const profile = await readProEntitlementProfile(
      profileClient(async () => ({
        data: {
          is_pro: true,
          creator_access: false,
          subscription_status: "active",
          trial_end: null,
        },
        error: null,
      })),
      "user-1",
      { timeoutMs: 1_000 }
    )
    assert.equal(profile?.is_pro, true)
  })
})
