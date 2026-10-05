import assert from "node:assert/strict"
import test from "node:test"
import {
  formatMoney,
  setMoney,
  sharedContent,
  sharedContentId,
  sumTradePnL,
  tradeLabel,
  writePath,
} from "./demoAdminModel.ts"

test("trade P&L edits stay on the trade and the derived total follows", () => {
  const trade = {
    id: "demo-trade-2-0",
    symbol: { ticker: "MNQ" },
    entryAt: "2026-10-01T15:00:00.000Z",
    realizedPnL: { amount: 500, currencyCode: "USD" },
  }
  assert.equal(tradeLabel(trade), "MNQ · +$500 · 2026-10-01")
  const updated = setMoney(trade, "realizedPnL", "900")
  assert.equal(sumTradePnL([trade]), 500)
  assert.equal(sumTradePnL([updated]), 900)
  assert.equal(formatMoney(900), "+$900")
})

test("shared content uses the Swift associated-value shape", () => {
  const message = writePath({ id: "m1", kind: "text" }, "sharedContent", sharedContent("trade", "demo-trade-2-0"))
  assert.deepEqual(sharedContentId(message), { kind: "trade", id: "demo-trade-2-0" })
  assert.deepEqual(message.sharedContent, { trade: { _0: "demo-trade-2-0" } })
})
