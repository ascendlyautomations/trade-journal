import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { createTradingPreferenceBundleCache } from "./tradingPreferenceBundleCache.ts"

describe("trading preference bundle cache", () => {
  it("shares one request across simultaneous loads and then reuses it", async () => {
    const cache = createTradingPreferenceBundleCache<{ n: number }>()
    let fetches = 0
    const fetchBundle = () => {
      fetches += 1
      return Promise.resolve({ n: fetches })
    }

    const [first, second] = await Promise.all([
      cache.load("user-1", fetchBundle),
      cache.load("user-1", fetchBundle),
    ])
    const third = await cache.load("user-1", fetchBundle)

    assert.equal(fetches, 1)
    assert.deepEqual(first, { n: 1 })
    assert.equal(second, first)
    assert.equal(third, first)
  })

  it("refetches after a Trading Rules save invalidates the bundle", async () => {
    const cache = createTradingPreferenceBundleCache<{ n: number }>()
    let fetches = 0
    const fetchBundle = () => {
      fetches += 1
      return Promise.resolve({ n: fetches })
    }

    await cache.load("user-1", fetchBundle)
    cache.invalidate("user-1")
    const next = await cache.load("user-1", fetchBundle)

    assert.equal(fetches, 2)
    assert.deepEqual(next, { n: 2 })
  })

  it("does not keep a bundle that finished after it was invalidated", async () => {
    const cache = createTradingPreferenceBundleCache<{ n: number }>()
    let release: (bundle: { n: number }) => void = () => {}
    const first = cache.load(
      "user-1",
      () =>
        new Promise((resolve) => {
          release = resolve
        })
    )
    cache.invalidate("user-1")
    release({ n: 1 })
    assert.deepEqual(await first, { n: 1 })

    let fetches = 0
    const next = await cache.load("user-1", () => {
      fetches += 1
      return Promise.resolve({ n: 2 })
    })
    assert.equal(fetches, 1)
    assert.deepEqual(next, { n: 2 })
  })
})
