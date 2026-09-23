import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  buildTradovateOrderAccountMap,
  missingOrderIdsForTradovateFills,
} from "./tradovateOrderAccountMap.ts"
import type { TradovateFillRaw, TradovateOrderRaw } from "./tradovateFillModels.ts"

describe("tradovateOrderAccountMap", () => {
  it("collects order ids missing from the initial order/list map", () => {
    const orders: TradovateOrderRaw[] = [{ id: 1, accountId: 65788591 }]
    const map = buildTradovateOrderAccountMap(orders)
    const fills: TradovateFillRaw[] = [
      {
        id: 10,
        orderId: 1,
        contractId: 4176766,
        timestamp: "2026-09-22T18:36:27.000Z",
        action: "Buy",
        qty: 1,
        price: 1,
      },
      {
        id: 11,
        orderId: 2,
        contractId: 4176766,
        timestamp: "2026-09-22T18:36:43.000Z",
        action: "Sell",
        qty: 1,
        price: 1,
      },
    ]
    assert.deepEqual(missingOrderIdsForTradovateFills(fills, map).sort(), ["2"])
  })
})
