import assert from "node:assert/strict"
import { describe, it } from "node:test"
import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "./database.types.ts"
import { fetchFeaturedPostCandidates } from "./featuredTradesCandidates.ts"

function tableClient(handler: {
  abortSignal: (signal: AbortSignal) => Promise<{
    data: unknown[] | null
    error: { message?: string } | null
  }>
}) {
  const builder: Record<string, unknown> = {}
  for (const method of ["select", "eq", "gte", "order", "limit"]) {
    builder[method] = () => builder
  }
  builder.abortSignal = handler.abortSignal
  return {
    from() {
      return builder
    },
  } as unknown as SupabaseClient<Database>
}

describe("fetchFeaturedPostCandidates timeout", () => {
  it("returns [] when the read times out so the homepage can render empty", async () => {
    const rows = await fetchFeaturedPostCandidates({
      client: tableClient({
        abortSignal(signal) {
          return new Promise((resolve) => {
            signal.addEventListener("abort", () => {
              resolve({
                data: [
                  {
                    id: "should-not-use",
                    pnl: 999,
                    trades: { is_public: true },
                    profiles: { is_private: false },
                  },
                ],
                error: { message: "AbortError: The user aborted a request." },
              })
            })
          })
        },
      }),
      timeoutMs: 40,
    })
    assert.deepEqual(rows, [])
  })

  it("keeps public discoverable rows on success", async () => {
    const rows = await fetchFeaturedPostCandidates({
      client: tableClient({
        async abortSignal() {
          return {
            data: [
              {
                id: "p1",
                created_at: new Date().toISOString(),
                pnl: 100,
                rr: 2,
                image_url: "user/trade-screenshot.png",
                trades: { is_public: true },
                profiles: { is_private: false, username: "nrl" },
              },
              {
                id: "no-image",
                created_at: new Date().toISOString(),
                pnl: 999,
                rr: 5,
                image_url: "",
                trades: { is_public: true },
                profiles: { is_private: false },
              },
              {
                id: "private",
                created_at: new Date().toISOString(),
                pnl: 500,
                trades: { is_public: true },
                profiles: { is_private: true },
              },
            ],
            error: null,
          }
        },
      }),
      timeoutMs: 1_000,
    })
    assert.equal(rows.length, 1)
    assert.equal(rows[0]?.id, "p1")
  })
})
