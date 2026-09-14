import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { TradovateMappingSyncCoalescer } from "./tradovateSyncCoalesce.ts"

describe("TradovateMappingSyncCoalescer", () => {
  it("debounces multiple schedule calls into one run", async () => {
    const coalescer = new TradovateMappingSyncCoalescer(20)
    let runs = 0
    coalescer.schedule("m1", async () => {
      runs += 1
    })
    coalescer.schedule("m1", async () => {
      runs += 1
    })
    await new Promise((r) => setTimeout(r, 60))
    assert.equal(runs, 1)
  })

  it("runs follow-up when event arrives during sync", async () => {
    const coalescer = new TradovateMappingSyncCoalescer(0)
    let runs = 0
    await coalescer.runNow("m1", async () => {
      runs += 1
      coalescer.schedule("m1", async () => {
        runs += 1
      })
      await new Promise((r) => setTimeout(r, 5))
    })
    await new Promise((r) => setTimeout(r, 30))
    assert.equal(runs, 2)
  })
})
