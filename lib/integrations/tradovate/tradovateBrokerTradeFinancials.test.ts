import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  computeTradovateBrokerTradeFinancials,
  type BrokerContractMeta,
} from "./tradovateBrokerTradeFinancials.ts"
import {
  mergeTradovateContractMetaMaps,
  resolveBrokerTradeTicker,
} from "./tradovateContractMeta.ts"
import type { ReconstructedLifecycleTrade } from "./tradeReconstruction.ts"

function lifecycle(
  patch: Partial<ReconstructedLifecycleTrade> & Pick<ReconstructedLifecycleTrade, "lifecycleKey">
): ReconstructedLifecycleTrade {
  return {
    contractId: "4399654",
    direction: "Short",
    contracts: 1,
    entryPrice: 29011,
    exitPrice: 29000,
    entryTime: "2026-09-15T14:00:00.000Z",
    exitTime: "2026-09-15T14:05:00.000Z",
    fillIds: ["1", "2"],
    points: 11,
    ...patch,
  }
}

describe("Tradovate broker trade financials (production-shaped)", () => {
  it("MNQ short with missing REST metadata uses execution ledger hints", () => {
    const merged = mergeTradovateContractMetaMaps(new Map(), [
      {
        external_contract_id: "4399654",
        symbol_root: "MNQ",
        contract_name: "MNQU6",
      },
    ])
    const contract = merged.get("4399654")!
    assert.equal(resolveBrokerTradeTicker({ contract, contractId: "4399654" }), "MNQ")

    const fin = computeTradovateBrokerTradeFinancials({
      lifecycle: lifecycle({
        lifecycleKey: "tradovate:v2:65788591:4399654:3",
      }),
      contract,
      contractIdKey: "4399654",
      feesByFillId: new Map(),
    })
    assert.equal(fin.ticker, "MNQ")
    assert.equal(fin.valuePerPoint, 2)
    assert.equal(fin.grossPnL, 22)
    assert.equal(fin.netPnL, 22)
    assert.equal(fin.numericTicker, false)
  })

  it("repairs broken persisted state: numeric ticker + null pnl projection", () => {
    const existingTicker = "4399654"
    const existingPnL = null
    assert.match(existingTicker, /^\d+$/)
    assert.equal(existingPnL, null)

    const contract = mergeTradovateContractMetaMaps(new Map(), [
      {
        external_contract_id: "4399654",
        symbol_root: "MNQ",
        contract_name: "MNQU6",
      },
    ]).get("4399654")!

    const fin = computeTradovateBrokerTradeFinancials({
      lifecycle: lifecycle({
        lifecycleKey: "tradovate:v2:65788591:4399654:3",
      }),
      contract,
      contractIdKey: "4399654",
      feesByFillId: new Map(),
    })

    assert.equal(fin.ticker, "MNQ")
    assert.equal(fin.netPnL, 22)
    // Upsert patch would include ticker + pnl (same broker_lifecycle_id, same trade id).
  })

  it("MGC long normalizes MGCV6 and computes non-null P&L", () => {
    const contract: BrokerContractMeta = mergeTradovateContractMetaMaps(new Map(), [
      {
        external_contract_id: "4176766",
        symbol_root: "MGC",
        contract_name: "MGCV6",
      },
    ]).get("4176766")!

    const fin = computeTradovateBrokerTradeFinancials({
      lifecycle: lifecycle({
        lifecycleKey: "tradovate:v2:65788591:4176766:1",
        contractId: "4176766",
        direction: "Long",
        entryPrice: 4348.4,
        exitPrice: 4348.1,
        points: -0.3,
        contracts: 1,
      }),
      contract,
      contractIdKey: "4176766",
      feesByFillId: new Map(),
    })

    assert.equal(fin.ticker, "MGC")
    assert.equal(fin.valuePerPoint, 10)
    assert.ok(Math.abs((fin.grossPnL ?? 0) + 3) < 0.01)
    assert.ok(Math.abs((fin.netPnL ?? 0) + 3) < 0.01)
  })

  it("REST contract endpoint failure still resolves from execution-only hints", () => {
    const fin = computeTradovateBrokerTradeFinancials({
      lifecycle: lifecycle({ lifecycleKey: "tradovate:v2:1:4470324:1", contractId: "4470324" }),
      contract: mergeTradovateContractMetaMaps(new Map(), [
        {
          external_contract_id: "4470324",
          symbol_root: "MNQ",
          contract_name: "MNQZ6",
        },
      ]).get("4470324"),
      contractIdKey: "4470324",
      feesByFillId: new Map(),
    })
    assert.equal(fin.ticker, "MNQ")
    assert.notEqual(fin.netPnL, null)
  })
})
