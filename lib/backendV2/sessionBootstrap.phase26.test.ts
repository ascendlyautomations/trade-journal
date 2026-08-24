import { describe, it, beforeEach } from "node:test"
import { beginSessionBootstrapFlight, getSessionBootstrapFlight, hasSessionBootstrapFlight, clearSessionBootstrapFlights, __resetSessionBootstrapFlightsForTests, } from "./sessionBootstrapSingleFlight.ts"
import { clearSessionBootstrapCache, writeSessionBootstrapCache, readSessionBootstrapCache, invalidateSessionBootstrap, } from "./sessionBootstrapCache.ts"
import { runSessionBootstrapRpcOnce, getSessionBootstrapRpcGateStats, __resetSessionBootstrapRpcGateForTests, } from "./sessionBootstrapRpcGate.ts"
import { sessionBootstrapFixture } from "./fixtures.ts"
import assert from "node:assert/strict"

describe("Backend V2 session single-flight (Phase 2.6)", () => {
  beforeEach(() => {
    clearSessionBootstrapCache()
    __resetSessionBootstrapFlightsForTests()
    __resetSessionBootstrapRpcGateForTests()
  })

  it("concurrent beginSessionBootstrapFlight shares one start()", async () => {
    let starts = 0
    const start = async () => {
      starts += 1
      await new Promise((r) => setTimeout(r, 20))
      return { ok: true, starts }
    }

    const [a, b, c] = await Promise.all([
      beginSessionBootstrapFlight("u1", start),
      beginSessionBootstrapFlight("u1", start),
      beginSessionBootstrapFlight("u1", start),
    ])

    assert.equal(starts, 1)
    assert.equal(a.starts, 1)
    assert.equal(b.starts, 1)
    assert.equal(c.starts, 1)
    assert.equal(hasSessionBootstrapFlight("u1"), true)
    assert.ok(getSessionBootstrapFlight("u1"))
  })

  it("reentrant start() cannot create a second flight (reserve-before-start)", async () => {
    let starts = 0
    let nestedJoinedExisting = false
    const result = await beginSessionBootstrapFlight("u-reenter", async () => {
      starts += 1
      // Synchronously re-enter before any await — old bug started a 2nd flight here.
      const nestedPromise = beginSessionBootstrapFlight("u-reenter", async () => {
        starts += 1
        return { nested: true }
      })
      nestedJoinedExisting =
        starts === 1 && nestedPromise === getSessionBootstrapFlight("u-reenter")
      await new Promise((r) => setTimeout(r, 5))
      // Do not await nestedPromise here — it is the same outer promise (would deadlock).
      return { outer: true }
    })

    assert.equal(starts, 1)
    assert.equal(nestedJoinedExisting, true)
    assert.equal(result.outer, true)
  })

  it("retains settled flight until invalidate", async () => {
    let starts = 0
    const start = async () => {
      starts += 1
      return { n: starts }
    }

    await beginSessionBootstrapFlight("u2", start)
    assert.equal(starts, 1)

    const again = await beginSessionBootstrapFlight("u2", start)
    assert.equal(starts, 1)
    assert.equal(again.n, 1)

    invalidateSessionBootstrap("u2")
    assert.equal(hasSessionBootstrapFlight("u2"), false)

    await beginSessionBootstrapFlight("u2", start)
    assert.equal(starts, 2)
  })

  it("failed flight allows retry", async () => {
    let starts = 0
    await assert.rejects(
      beginSessionBootstrapFlight("u3", async () => {
        starts += 1
        throw new Error("boom")
      })
    )
    assert.equal(hasSessionBootstrapFlight("u3"), false)

    const ok = await beginSessionBootstrapFlight("u3", async () => {
      starts += 1
      return { ok: true }
    })
    assert.equal(starts, 2)
    assert.equal(ok.ok, true)
  })

  it("cache clear also clears flights and rpc gate", async () => {
    writeSessionBootstrapCache("u4", sessionBootstrapFixture, "rpc")
    await beginSessionBootstrapFlight("u4", async () => ({ done: true }))
    await runSessionBootstrapRpcOnce(async () => ({
      data: { ok: true },
      error: null,
    }))
    assert.ok(readSessionBootstrapCache("u4"))
    assert.equal(hasSessionBootstrapFlight("u4"), true)
    assert.equal(getSessionBootstrapRpcGateStats().networkStarts, 1)

    clearSessionBootstrapCache()
    assert.equal(readSessionBootstrapCache("u4"), null)
    assert.equal(hasSessionBootstrapFlight("u4"), false)
    assert.equal(getSessionBootstrapRpcGateStats().hasPromise, false)
  })

  it("clearSessionBootstrapFlights is user-scoped", async () => {
    await beginSessionBootstrapFlight("a", async () => 1)
    await beginSessionBootstrapFlight("b", async () => 2)
    clearSessionBootstrapFlights("a")
    assert.equal(hasSessionBootstrapFlight("a"), false)
    assert.equal(hasSessionBootstrapFlight("b"), true)
  })
})

describe("Backend V2 session RPC network gate", () => {
  beforeEach(() => {
    __resetSessionBootstrapRpcGateForTests()
  })

  it("concurrent runSessionBootstrapRpcOnce invokes network once", async () => {
    let network = 0
    const invoke = async () => {
      network += 1
      await new Promise((r) => setTimeout(r, 15))
      return { data: { n: network }, error: null }
    }

    const [a, b, c] = await Promise.all([
      runSessionBootstrapRpcOnce(invoke),
      runSessionBootstrapRpcOnce(invoke),
      runSessionBootstrapRpcOnce(invoke),
    ])

    assert.equal(network, 1)
    assert.equal(getSessionBootstrapRpcGateStats().networkStarts, 1)
    assert.equal(getSessionBootstrapRpcGateStats().reuses, 2)
    assert.deepEqual(a.data, { n: 1 })
    assert.deepEqual(b.data, { n: 1 })
    assert.deepEqual(c.data, { n: 1 })
  })

  it("reentrant invoke path cannot double-network", async () => {
    let network = 0
    let nestedJoinedExisting = false
    await runSessionBootstrapRpcOnce(async () => {
      network += 1
      const nestedPromise = runSessionBootstrapRpcOnce(async () => {
        network += 1
        return { data: { nested: true }, error: null }
      })
      nestedJoinedExisting =
        network === 1 && getSessionBootstrapRpcGateStats().reuses >= 1
      await new Promise((r) => setTimeout(r, 5))
      // Do not await nestedPromise — same reserved promise (would deadlock).
      void nestedPromise
      return { data: { outer: true }, error: null }
    })
    assert.equal(network, 1)
    assert.equal(nestedJoinedExisting, true)
  })
})
export {}
