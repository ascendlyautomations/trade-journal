import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { computeTradovateBrokerTradeFinancials } from "./tradovateBrokerTradeFinancials.ts"
import {
  MGC_CONTRACT_ID,
  MNQ_CONTRACT_U6,
  MNQ_CONTRACT_Z6,
  TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE,
  tradovateMgcFillsMissingProfitableRoundTrip,
  tradovatePerformanceSep2026ReconstructionFills,
} from "./tradovatePerformanceSep2026Fixture.ts"
import {
  buildTradovateOrderAccountMap,
  filterParsedTradovateFillsForAccount,
  missingOrderIdsForTradovateFills,
} from "./tradovateOrderAccountMap.ts"
import {
  reconstructAllCompletedTrades,
  type ReconstructedLifecycleTrade,
} from "./tradeReconstruction.ts"
import type { TradovateFillRaw } from "./tradovateFillModels.ts"

const MGC_META = {
  symbolRoot: "MGC",
  contractName: "MGCV6",
  executionSymbolRoot: "MGC",
  executionContractName: "MGCV6",
  valuePerPoint: 10,
}

const MNQ_META = {
  symbolRoot: "MNQ",
  contractName: "MNQU6",
  valuePerPoint: 2,
}

function sumNetPnL(trades: ReconstructedLifecycleTrade[], contractId: string): number {
  let total = 0
  for (const lifecycle of trades) {
    if (lifecycle.contractId !== contractId) continue
    const fin = computeTradovateBrokerTradeFinancials({
      lifecycle,
      contract: contractId === MGC_CONTRACT_ID ? MGC_META : MNQ_META,
      contractIdKey: contractId,
      feesByFillId: new Map(),
    })
    assert.notEqual(fin.netPnL, null, `expected pnl for ${lifecycle.lifecycleKey}`)
    total += fin.netPnL!
  }
  return total
}

function mgcLifecycles(trades: ReconstructedLifecycleTrade[]) {
  return trades.filter((t) => t.contractId === MGC_CONTRACT_ID)
}

describe("Tradovate Performance Sep 2026 MGC regression", () => {
  it("order account hydration includes fills whose orders were absent from order/list", () => {
    const orderAccountById = buildTradovateOrderAccountMap([])
    const fillsRaw: TradovateFillRaw[] = [
      {
        id: "660290950326",
        orderId: "999001",
        contractId: MGC_CONTRACT_ID,
        timestamp: "2026-09-22T18:36:27.000Z",
        action: "Buy",
        qty: 2,
        price: 4358.7,
      },
    ]
    assert.deepEqual(missingOrderIdsForTradovateFills(fillsRaw, orderAccountById), ["999001"])
    orderAccountById.set("999001", TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE)
    const scoped = filterParsedTradovateFillsForAccount(
      fillsRaw,
      TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE,
      orderAccountById
    )
    assert.equal(scoped.length, 1)
  })

  it("production gap: without +60 fills, MGC net is -55 (matches broken TradeTraxs)", () => {
    const { completed } = reconstructAllCompletedTrades(
      tradovateMgcFillsMissingProfitableRoundTrip(),
      TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE
    )
    const mgc = mgcLifecycles(completed)
    assert.equal(mgc.length, 5)
    const total = sumNetPnL(completed, MGC_CONTRACT_ID)
    assert.ok(Math.abs(total + 55) < 0.01, `expected -55 got ${total}`)
    const shortLoss = mgc.find((t) => t.fillIds.includes("660290950280"))
    assert.ok(shortLoss)
    assert.equal(shortLoss.direction, "Short")
    assert.equal(shortLoss.contracts, 2)
    assert.ok(Math.abs(sumNetPnL([shortLoss], MGC_CONTRACT_ID) + 44) < 0.01)
  })

  it("full fixture: MGC +5, MNQ -45, overall -40; includes profitable long after flat", () => {
    const { completed } = reconstructAllCompletedTrades(
      tradovatePerformanceSep2026ReconstructionFills(),
      TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE
    )
    const mgc = mgcLifecycles(completed)
    assert.equal(mgc.length, 6)

    const longWinner = mgc.find((t) => t.fillIds.includes("660290950326"))
    assert.ok(longWinner, "missing MGC long lifecycle for fill 660290950326")
    assert.equal(longWinner.direction, "Long")
    assert.equal(longWinner.contracts, 2)
    assert.ok(longWinner.fillIds.includes("660290950296"))
    assert.ok(longWinner.fillIds.includes("660290950290"))

    const mgcTotal = sumNetPnL(completed, MGC_CONTRACT_ID)
    assert.ok(Math.abs(mgcTotal - 5) < 0.01, `MGC total expected +5 got ${mgcTotal}`)

    const mnqUTotal = sumNetPnL(
      completed.filter((t) => t.contractId === MNQ_CONTRACT_U6),
      MNQ_CONTRACT_U6
    )
    const mnqZTotal = sumNetPnL(
      completed.filter((t) => t.contractId === MNQ_CONTRACT_Z6),
      MNQ_CONTRACT_Z6
    )
    assert.ok(Math.abs(mnqUTotal + 11.5) < 0.01, `MNQU6 expected -11.5 got ${mnqUTotal}`)
    assert.ok(Math.abs(mnqZTotal + 33.5) < 0.01, `MNQZ6 expected -33.5 got ${mnqZTotal}`)
    assert.ok(Math.abs(mnqUTotal + mnqZTotal + 45) < 0.01)

    const overall =
      mgcTotal +
      mnqUTotal +
      mnqZTotal
    assert.ok(Math.abs(overall + 40) < 0.01, `overall expected -40 got ${overall}`)
  })

  it("repeated reconstruction is idempotent (same lifecycle keys, no extra round trips)", () => {
    const fills = tradovatePerformanceSep2026ReconstructionFills()
    const first = reconstructAllCompletedTrades(fills, TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE)
    const second = reconstructAllCompletedTrades(fills, TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE)
    assert.equal(first.completed.length, second.completed.length)
    assert.deepEqual(
      first.completed.map((t) => t.lifecycleKey).sort(),
      second.completed.map((t) => t.lifecycleKey).sort()
    )
  })
})
