import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  getOrCreateRoomSharedPostInflight,
  getOrCreateSharedTradeInflight,
} from "./roomSharedContentEmbedCache.ts"

/**
 * Simulates React 18 Strict Mode: effect A starts a shared inflight fetch; cleanup sets
 * `cancelled` so the async factory must not call `setState` for A. Effect B attaches
 * `.then()` to the same promise and applies UI when it resolves.
 */
describe("roomSharedContentEmbedCache — inflight promise subscribers", () => {
  it("post: late .then subscriber receives resolved value (Strict Mode pattern)", async () => {
    const key = `post:${Date.now()}`
    let resolveFetch!: (v: { id: string }) => void
    const fetchDone = new Promise<{ id: string }>((r) => {
      resolveFetch = r
    })

    const inflight = getOrCreateRoomSharedPostInflight(key, async () => {
      return fetchDone
    })

    const lateResults: { id: string }[] = []
    void inflight.then((row) => {
      lateResults.push(row as { id: string })
    })

    resolveFetch({ id: "embed-1" })
    await inflight

    assert.deepEqual(lateResults, [{ id: "embed-1" }])
  })

  it("trade: late .then subscriber receives resolved value", async () => {
    const key = `trade:${Date.now()}`
    let resolveFetch!: (v: { ticker: string }) => void
    const fetchDone = new Promise<{ ticker: string }>((r) => {
      resolveFetch = r
    })

    const inflight = getOrCreateSharedTradeInflight(key, async () => fetchDone)

    const lateResults: { ticker: string }[] = []
    void inflight.then((row) => {
      lateResults.push(row as { ticker: string })
    })

    resolveFetch({ ticker: "ES" })
    await inflight

    assert.deepEqual(lateResults, [{ ticker: "ES" }])
  })

  it("post: after inflight completes, map is cleared; new call creates new promise", async () => {
    const key = `post-reuse:${Date.now()}`
    const p1 = getOrCreateRoomSharedPostInflight(key, async () => ({ v: 1 }))
    assert.deepEqual(await p1, { v: 1 })
    const p2 = getOrCreateRoomSharedPostInflight(key, async () => ({ v: 2 }))
    assert.notStrictEqual(p1, p2)
    assert.deepEqual(await p2, { v: 2 })
  })
})
