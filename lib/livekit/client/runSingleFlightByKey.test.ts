import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { runSingleFlightByKey } from "./runSingleFlightByKey.ts"

describe("runSingleFlightByKey", () => {
  it("dedupes concurrent callers with the same key", async () => {
    const flights = new Map<string, Promise<unknown>>()
    let runs = 0
    const p1 = runSingleFlightByKey(flights, "s1", false, async () => {
      runs += 1
      await new Promise((r) => setTimeout(r, 20))
      return "a"
    })
    const p2 = runSingleFlightByKey(flights, "s1", false, async () => {
      runs += 1
      return "b"
    })
    const [a, b] = await Promise.all([p1, p2])
    assert.equal(a, "a")
    assert.equal(b, "a")
    assert.equal(runs, 1)
    assert.equal(flights.size, 0)
  })

  it("forceNewFlight awaits prior then starts a new run", async () => {
    const flights = new Map<string, Promise<unknown>>()
    const order: string[] = []
    const first = runSingleFlightByKey(flights, "s2", false, async () => {
      order.push("start1")
      await new Promise((r) => setTimeout(r, 10))
      order.push("end1")
      return 1
    })
    const second = runSingleFlightByKey(flights, "s2", true, async () => {
      order.push("start2")
      return 2
    })
    assert.equal(await first, 1)
    assert.equal(await second, 2)
    assert.deepEqual(order, ["start1", "end1", "start2"])
  })
})
