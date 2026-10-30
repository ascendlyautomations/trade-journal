import assert from "node:assert/strict"
import { describe, it } from "node:test"
import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "./database.types.ts"
import { loadPublicUserReviews } from "./landingPublicReviews.ts"
import type { PublicUserReview } from "./userReviewDisplay.ts"

const SAMPLE: PublicUserReview = {
  id: "11111111-1111-4111-8111-111111111111",
  rating: 5,
  title: "Great",
  review: "Helped my journal.",
  would_recommend: true,
  featured: true,
  created_at: "2026-10-01T00:00:00.000Z",
  display_name: "Alex",
  username_snapshot: "alex",
  avatar_snapshot: null,
}

function rpcClient(handler: {
  abortSignal: (signal: AbortSignal) => Promise<{
    data: PublicUserReview[] | null
    error: { message?: string; code?: string } | null
  }>
}) {
  return {
    rpc() {
      return {
        abortSignal: handler.abortSignal,
      }
    },
  } as unknown as SupabaseClient<Database>
}

describe("loadPublicUserReviews timeout", () => {
  it("returns reviews when the RPC succeeds", async () => {
    const reviews = await loadPublicUserReviews({
      client: rpcClient({
        async abortSignal() {
          return { data: [SAMPLE], error: null }
        },
      }),
      timeoutMs: 1_000,
    })
    assert.equal(reviews.length, 1)
    assert.equal(reviews[0]?.title, "Great")
  })

  it("returns [] when the RPC is aborted by the read timeout", async () => {
    const reviews = await loadPublicUserReviews({
      client: rpcClient({
        abortSignal(signal) {
          return new Promise((resolve) => {
            signal.addEventListener("abort", () => {
              resolve({
                data: null,
                error: { message: "AbortError: The user aborted a request." },
              })
            })
          })
        },
      }),
      timeoutMs: 40,
    })
    assert.deepEqual(reviews, [])
  })
})
