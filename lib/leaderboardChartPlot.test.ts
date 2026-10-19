import { describe, it } from "node:test"
import assert from "node:assert/strict"
import type { LeaderboardChartRow } from "./leaderboardChart.ts"
import {
  formatLeaderboardChartTooltipMetric,
  leaderboardChartPlotRows,
} from "./leaderboardChartPlot.ts"

function chartRow(
  overrides: Partial<LeaderboardChartRow> & Pick<LeaderboardChartRow, "contributorCount">
): LeaderboardChartRow {
  return {
    bucketId: "2026-01-15",
    label: "1/15/2026",
    sortKey: 20260115,
    average: 100,
    best: 200,
    worst: 50,
    you: null,
    contributorCount: overrides.contributorCount,
    ...overrides,
  }
}

describe("leaderboardChartPlotRows", () => {
  it("uses Best only when one contributor contributed", () => {
    const [plot] = leaderboardChartPlotRows([
      chartRow({ contributorCount: 1, average: 500, best: 500, worst: 500 }),
    ])
    assert.equal(plot.averagePlot, null)
    assert.equal(plot.bestPlot, 500)
    assert.equal(plot.worstPlot, null)
  })

  it("plots Average, Best, and Worst when values differ for 2+ contributors", () => {
    const [plot] = leaderboardChartPlotRows([chartRow({ contributorCount: 3 })])
    assert.equal(plot.averagePlot, 100)
    assert.equal(plot.bestPlot, 200)
    assert.equal(plot.worstPlot, 50)
  })

  it("omits overlapping Best/Worst when they match Average", () => {
    const [plot] = leaderboardChartPlotRows([
      chartRow({
        contributorCount: 2,
        average: 100,
        best: 100,
        worst: 40,
      }),
    ])
    assert.equal(plot.averagePlot, 100)
    assert.equal(plot.bestPlot, null)
    assert.equal(plot.worstPlot, 40)
  })

  it("does not connect single- and multi-contributor days via Average", () => {
    const plots = leaderboardChartPlotRows([
      chartRow({ contributorCount: 1, average: 10, best: 10, worst: 10 }),
      chartRow({ contributorCount: 2, average: 20, best: 30, worst: 10 }),
    ])
    assert.equal(plots[0]?.averagePlot, null)
    assert.equal(plots[1]?.averagePlot, 20)
  })
})

describe("formatLeaderboardChartTooltipMetric", () => {
  it("shows em dash for Average and Worst with one contributor", () => {
    assert.equal(
      formatLeaderboardChartTooltipMetric("average", 400, 1),
      "—"
    )
    assert.equal(formatLeaderboardChartTooltipMetric("worst", 400, 1), "—")
    assert.equal(
      formatLeaderboardChartTooltipMetric("best", 400, 1),
      "$400.00"
    )
  })

  it("formats all metrics for multiple contributors", () => {
    assert.equal(
      formatLeaderboardChartTooltipMetric("average", 100, 3),
      "$100.00"
    )
    assert.equal(formatLeaderboardChartTooltipMetric("worst", -50, 3), "-$50.00")
  })
})

export {}
