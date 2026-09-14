import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  reconstructAllCompletedTrades,
  reconstructCompletedTradesForContract,
  type ReconstructionFill,
} from "./tradeReconstruction.ts"

const M = "mapping-1"
const C = "100"

function fill(
  id: string,
  action: "Buy" | "Sell",
  qty: number,
  price: number,
  timestamp: string
): ReconstructionFill {
  return {
    fillId: id,
    contractId: C,
    timestamp,
    action,
    qty,
    price,
  }
}

function lifecycles(fills: ReconstructionFill[]) {
  return reconstructCompletedTradesForContract(fills, {
    mappingId: M,
    contractId: C,
  })
}

describe("tradovate trade reconstruction", () => {
  it("1. Buy1 → Sell1 simple long", () => {
    const { completed } = lifecycles([
      fill("1", "Buy", 1, 100, "2026-01-01T10:00:00Z"),
      fill("2", "Sell", 1, 110, "2026-01-01T10:05:00Z"),
    ])
    assert.equal(completed.length, 1)
    assert.equal(completed[0].direction, "Long")
    assert.equal(completed[0].contracts, 1)
    assert.equal(completed[0].entryPrice, 100)
    assert.equal(completed[0].exitPrice, 110)
    assert.equal(completed[0].points, 10)
  })

  it("2. Sell1 → Buy1 simple short", () => {
    const { completed } = lifecycles([
      fill("1", "Sell", 1, 200, "2026-01-01T10:00:00Z"),
      fill("2", "Buy", 1, 190, "2026-01-01T10:05:00Z"),
    ])
    assert.equal(completed.length, 1)
    assert.equal(completed[0].direction, "Short")
    assert.equal(completed[0].points, 10)
  })

  it("3. Buy1 + Buy1 → Sell2 scale in", () => {
    const { completed } = lifecycles([
      fill("1", "Buy", 1, 100, "2026-01-01T10:00:00Z"),
      fill("2", "Buy", 1, 104, "2026-01-01T10:01:00Z"),
      fill("3", "Sell", 2, 110, "2026-01-01T10:10:00Z"),
    ])
    assert.equal(completed.length, 1)
    assert.equal(completed[0].contracts, 2)
    assert.equal(completed[0].entryPrice, 102)
    assert.equal(completed[0].exitPrice, 110)
  })

  it("4. Buy2 → Sell1 → Sell1 scale out", () => {
    const { completed } = lifecycles([
      fill("1", "Buy", 2, 50, "2026-01-01T10:00:00Z"),
      fill("2", "Sell", 1, 55, "2026-01-01T10:05:00Z"),
      fill("3", "Sell", 1, 56, "2026-01-01T10:06:00Z"),
    ])
    assert.equal(completed.length, 1)
    assert.equal(completed[0].contracts, 2)
    assert.equal(completed[0].exitPrice, 55.5)
  })

  it("5. Buy1 → Buy1 → Sell1 → Sell1 scale in and out", () => {
    const { completed } = lifecycles([
      fill("1", "Buy", 1, 10, "2026-01-01T10:00:00Z"),
      fill("2", "Buy", 1, 12, "2026-01-01T10:01:00Z"),
      fill("3", "Sell", 1, 14, "2026-01-01T10:02:00Z"),
      fill("4", "Sell", 1, 15, "2026-01-01T10:03:00Z"),
    ])
    assert.equal(completed.length, 1)
    assert.equal(completed[0].contracts, 2)
    assert.equal(completed[0].entryPrice, 11)
  })

  it("6. Buy1 → Sell2 long reversal closes long and leaves short open", () => {
    const { completed, openSignedQty } = lifecycles([
      fill("1", "Buy", 1, 100, "2026-01-01T10:00:00Z"),
      fill("2", "Sell", 2, 95, "2026-01-01T10:05:00Z"),
    ])
    assert.equal(completed.length, 1)
    assert.equal(completed[0].direction, "Long")
    assert.equal(completed[0].contracts, 1)
    assert.equal(openSignedQty, -1)
  })

  it("7. Sell1 → Buy2 short reversal closes short and leaves long open", () => {
    const { completed, openSignedQty } = lifecycles([
      fill("1", "Sell", 1, 300, "2026-01-01T10:00:00Z"),
      fill("2", "Buy", 2, 305, "2026-01-01T10:05:00Z"),
    ])
    assert.equal(completed.length, 1)
    assert.equal(completed[0].direction, "Short")
    assert.equal(openSignedQty, 1)
  })

  it("8. partial fills same order (two fills, one lifecycle)", () => {
    const { completed } = lifecycles([
      fill("1", "Buy", 1, 100, "2026-01-01T10:00:00Z"),
      fill("2", "Buy", 1, 101, "2026-01-01T10:00:01Z"),
      fill("3", "Sell", 2, 105, "2026-01-01T10:05:00Z"),
    ])
    assert.equal(completed.length, 1)
    assert.equal(completed[0].contracts, 2)
  })

  it("9. two round trips same symbol same day", () => {
    const { completed } = lifecycles([
      fill("1", "Buy", 1, 10, "2026-01-01T09:00:00Z"),
      fill("2", "Sell", 1, 11, "2026-01-01T09:30:00Z"),
      fill("3", "Buy", 1, 12, "2026-01-01T10:00:00Z"),
      fill("4", "Sell", 1, 13, "2026-01-01T10:30:00Z"),
    ])
    assert.equal(completed.length, 2)
    assert.equal(completed[0].contracts, 1)
    assert.equal(completed[1].contracts, 1)
    assert.notEqual(completed[0].lifecycleKey, completed[1].lifecycleKey)
  })

  it("10. open position closes on later sync", () => {
    const first = lifecycles([fill("1", "Buy", 1, 50, "2026-01-01T10:00:00Z")])
    assert.equal(first.completed.length, 0)
    assert.equal(first.openSignedQty, 1)

    const second = lifecycles([
      fill("1", "Buy", 1, 50, "2026-01-01T10:00:00Z"),
      fill("2", "Sell", 1, 55, "2026-01-01T11:00:00Z"),
    ])
    assert.equal(second.completed.length, 1)
    assert.equal(second.openSignedQty, 0)
  })

  it("11. duplicate provider execution id dedupes before reconstruction", () => {
    const { completed } = reconstructAllCompletedTrades(
      [
        fill("1", "Buy", 1, 10, "2026-01-01T10:00:00Z"),
        fill("1", "Buy", 1, 10, "2026-01-01T10:00:00Z"),
        fill("2", "Sell", 1, 11, "2026-01-01T10:05:00Z"),
      ],
      M
    )
    assert.equal(completed.length, 1)
  })

  it("12. identical timestamps use fill id ordering", () => {
    const { completed } = lifecycles([
      fill("2", "Buy", 1, 10, "2026-01-01T10:00:00Z"),
      fill("10", "Sell", 1, 11, "2026-01-01T10:00:00Z"),
    ])
    assert.equal(completed.length, 1)
    assert.deepEqual(completed[0].fillIds, ["2", "10"])
  })

  it("14. two contracts stay independent", () => {
    const { completed, openByContract } = reconstructAllCompletedTrades(
      [
        fill("1", "Buy", 1, 10, "2026-01-01T10:00:00Z"),
        { ...fill("2", "Sell", 1, 11, "2026-01-01T10:05:00Z") },
        {
          fillId: "3",
          contractId: "200",
          timestamp: "2026-01-01T10:00:00Z",
          action: "Sell",
          qty: 1,
          price: 20,
        },
      ],
      M
    )
    assert.equal(completed.length, 1)
    assert.equal(openByContract.get("200"), -1)
  })
})
