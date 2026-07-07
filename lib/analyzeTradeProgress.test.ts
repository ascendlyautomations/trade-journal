import { describe, expect, it } from "vitest"
import {
  createAnalyzeProgressController,
  getAnalyzeProgressStages,
} from "./analyzeTradeProgress"

describe("analyzeTradeProgress", () => {
  it("includes chart review stage when screenshots exist", () => {
    const stages = getAnalyzeProgressStages(true)
    expect(stages.some((s) => s.label.includes("charts"))).toBe(true)
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
      expect(values[i]).toBeGreaterThanOrEqual(values[i - 1]!)
    }
    expect(values.at(-1)).toBe(100)
  })
})
