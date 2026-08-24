import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  createAnalyzeProgressController,
  getAnalyzeProgressStages,
} from "./analyzeTradeProgress.ts"

describe("analyzeTradeProgress", () => {
  it("includes chart review stage when screenshots exist", () => {
    const stages = getAnalyzeProgressStages(true)
    assert.ok(stages.some((s) => s.label.includes("charts")))
  })

  it("never decreases simulated progress", async () => {
    const values: number[] = []
    const controller = createAnalyzeProgressController(false, (percent) => {
      values.push(percent)
    })

    controller.start()
    await new Promise((resolve) => setTimeout(resolve, 400))
    controller.markApiComplete()
    await controller.waitForCompletion()
    controller.stop()

    for (let i = 1; i < values.length; i++) {
      assert.ok(values[i]! >= values[i - 1]!)
    }
    assert.equal(values.at(-1), 100)
  })
})
