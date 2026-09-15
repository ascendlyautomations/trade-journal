import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  reconstructAllCompletedTrades,
  type ReconstructionFill,
} from "../tradovate/tradeReconstruction.ts"

const M = "rithmic-mapping-1"
const C = "CME:MNQH6"

function fill(
  id: string,
  action: "Buy" | "Sell",
  qty: number,
  price: number,
  timestamp: string
): ReconstructionFill {
  return {
    fillId: `F|I|A|${id}`,
    contractId: C,
    timestamp,
    action,
    qty,
    price,
  }
}

function lifecycles(fills: ReconstructionFill[]) {
  return reconstructAllCompletedTrades(fills, M, { lifecycleProvider: "rithmic" })
}

describe("Rithmic trade reconstruction (shared engine)", () => {
  it("simple long", () => {
    const { completed } = lifecycles([
      fill("1", "Buy", 1, 100, "2026-01-01T10:00:00.000Z"),
      fill("2", "Sell", 1, 110, "2026-01-01T10:05:00.000Z"),
    ])
    assert.equal(completed.length, 1)
    assert.equal(completed[0].direction, "Long")
    assert.match(completed[0].lifecycleKey, /^rithmic:/)
  })

  it("scale in", () => {
    const { completed } = lifecycles([
      fill("1", "Buy", 1, 100, "2026-01-01T10:00:00Z"),
      fill("2", "Buy", 2, 104, "2026-01-01T10:01:00Z"),
      fill("3", "Sell", 3, 110, "2026-01-01T10:10:00Z"),
    ])
    assert.equal(completed.length, 1)
    assert.equal(completed[0].contracts, 3)
    assert.equal(completed[0].entryPrice, 102.66666666666667)
  })

  it("reversal leaves open short", () => {
    const { completed, openByContract } = lifecycles([
      fill("1", "Buy", 1, 100, "2026-01-01T10:00:00Z"),
      fill("2", "Sell", 2, 95, "2026-01-01T10:05:00Z"),
    ])
    assert.equal(completed.length, 1)
    assert.equal(openByContract.get(C), -1)
  })

  it("open position — no completed trade until flat", () => {
    const { completed } = lifecycles([fill("1", "Buy", 5, 50, "2026-01-01T10:00:00Z")])
    assert.equal(completed.length, 0)
  })

  it("duplicate fill id dedupes on repeated import", () => {
    const { completed } = reconstructAllCompletedTrades(
      [
        fill("1", "Buy", 1, 10, "2026-01-01T10:00:00Z"),
        fill("1", "Buy", 1, 10, "2026-01-01T10:00:00Z"),
        fill("2", "Sell", 1, 11, "2026-01-01T10:05:00Z"),
      ],
      M,
      { lifecycleProvider: "rithmic" }
    )
    assert.equal(completed.length, 1)
  })

  it("out-of-order fill ids still reconstruct with timestamp sort", () => {
    const { completed } = lifecycles([
      fill("10", "Sell", 1, 11, "2026-01-01T10:05:00Z"),
      fill("2", "Buy", 1, 10, "2026-01-01T10:00:00Z"),
    ])
    assert.equal(completed.length, 1)
    assert.equal(completed[0].direction, "Long")
  })
})
