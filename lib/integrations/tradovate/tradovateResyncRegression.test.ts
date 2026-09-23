import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  mergeTradovateContractMetaMaps,
  mergeTradovateExecutionContractFields,
} from "./tradovateContractMeta.ts"
import { computeTradovateBrokerTradeFinancials } from "./tradovateBrokerTradeFinancials.ts"
import { mergeBrokerTradeFinancialFields } from "./brokerTradeAuthoritativeMerge.ts"
import type { ReconstructedLifecycleTrade } from "./tradeReconstruction.ts"

function mnqLifecycle(
  patch: Partial<ReconstructedLifecycleTrade> & {
    lifecycleKey: string
    contractId?: string
    entryPrice: number
    exitPrice: number
    points: number
    direction?: "Long" | "Short"
  }
): ReconstructedLifecycleTrade {
  return {
    contractId: patch.contractId ?? "4399654",
    direction: patch.direction ?? "Short",
    contracts: 1,
    entryPrice: patch.entryPrice,
    exitPrice: patch.exitPrice,
    entryTime: "2026-09-15T14:00:00.000Z",
    exitTime: "2026-09-15T14:05:00.000Z",
    fillIds: ["1", "2"],
    points: patch.points,
    lifecycleKey: patch.lifecycleKey,
  }
}

describe("Tradovate resync regression (MNQ)", () => {
  const executionHints = [
    {
      external_contract_id: "4399654",
      symbol_root: "MNQ",
      contract_name: "MNQU6",
    },
    {
      external_contract_id: "4470324",
      symbol_root: "MNQ",
      contract_name: "MNQZ6",
    },
  ]

  it("execution enrichment does not wipe MNQ symbol_root with numeric REST metadata", () => {
    const merged = mergeTradovateExecutionContractFields(
      { symbol_root: "MNQ", contract_name: "MNQU6" },
      { symbol_root: "4399654", contract_name: "" }
    )
    assert.equal(merged.symbol_root, "MNQ")
    assert.equal(merged.contract_name, "MNQU6")
  })

  const cases: Array<{
    label: string
    lifecycle: ReconstructedLifecycleTrade
    contractId: string
  }> = [
    {
      label: "stored pnl -17.00 (long loss)",
      contractId: "4399654",
      lifecycle: mnqLifecycle({
        lifecycleKey: "tradovate:v2:1:4399654:1",
        direction: "Long",
        entryPrice: 29000,
        exitPrice: 28991.5,
        points: -8.5,
      }),
    },
    {
      label: "stored pnl +22.00 short",
      contractId: "4399654",
      lifecycle: mnqLifecycle({
        lifecycleKey: "tradovate:v2:1:4399654:2",
        entryPrice: 29011,
        exitPrice: 29000,
        points: 11,
      }),
    },
    {
      label: "stored pnl -11.50 long",
      contractId: "4470324",
      lifecycle: mnqLifecycle({
        lifecycleKey: "tradovate:v2:1:4470324:1",
        contractId: "4470324",
        direction: "Long",
        entryPrice: 29000,
        exitPrice: 28994.25,
        points: -5.75,
      }),
    },
    {
      label: "stored pnl -11.00 long",
      contractId: "4470324",
      lifecycle: mnqLifecycle({
        lifecycleKey: "tradovate:v2:1:4470324:2",
        contractId: "4470324",
        direction: "Long",
        entryPrice: 29000,
        exitPrice: 28994.5,
        points: -5.5,
      }),
    },
    {
      label: "stored pnl -16.50 long",
      contractId: "4399654",
      lifecycle: mnqLifecycle({
        lifecycleKey: "tradovate:v2:1:4399654:3",
        direction: "Long",
        entryPrice: 29000,
        exitPrice: 28991.75,
        points: -8.25,
      }),
    },
    {
      label: "stored pnl -11.00 long",
      contractId: "4399654",
      lifecycle: mnqLifecycle({
        lifecycleKey: "tradovate:v2:1:4399654:4",
        direction: "Long",
        entryPrice: 29000,
        exitPrice: 28994.5,
        points: -5.5,
      }),
    },
  ]

  for (const c of cases) {
    it(`calculates MNQ net P&L for ${c.label} after REST numeric poison + merge`, () => {
      const contracts = mergeTradovateContractMetaMaps(
        new Map([
          [
            c.contractId,
            {
              contractId: c.contractId,
              contractName: "",
              symbolRoot: c.contractId,
              valuePerPoint: null,
            },
          ],
        ]),
        executionHints
      )
      const contract = contracts.get(c.contractId)
      const fin = computeTradovateBrokerTradeFinancials({
        lifecycle: c.lifecycle,
        contract,
        contractIdKey: c.contractId,
        feesByFillId: new Map(),
      })
      assert.equal(fin.ticker, "MNQ")
      const expectedNet = c.lifecycle.points * 2 * c.lifecycle.contracts
      assert.equal(fin.netPnL, expectedNet)
      assert.equal(fin.nullReason, "ok")
    })
  }

  it("idempotent re-import: null incoming pnl does not clobber stored -17", () => {
    const contracts = mergeTradovateContractMetaMaps(new Map(), executionHints)
    const fin = computeTradovateBrokerTradeFinancials({
      lifecycle: mnqLifecycle({
        lifecycleKey: "tradovate:v2:1:4399654:resync",
        direction: "Long",
        entryPrice: 29000,
        exitPrice: 28991.5,
        points: -8.5,
      }),
      contract: contracts.get("4399654"),
      contractIdKey: "4399654",
      feesByFillId: new Map(),
    })
    assert.equal(fin.netPnL, -17)

    const poisoned = computeTradovateBrokerTradeFinancials({
      lifecycle: mnqLifecycle({
        lifecycleKey: "tradovate:v2:1:4399654:resync",
        direction: "Long",
        entryPrice: 29000,
        exitPrice: 28991.5,
        points: -8.5,
      }),
      contract: undefined,
      contractIdKey: "4399654",
      feesByFillId: new Map(),
    })
    assert.equal(poisoned.netPnL, null)

    const merged = mergeBrokerTradeFinancialFields({
      existingPnL: -17,
      existingTicker: "MNQ",
      incomingPnL: poisoned.netPnL,
      incomingTicker: poisoned.ticker,
    })
    assert.equal(merged.finalPnL, -17)
    assert.equal(merged.finalTicker, "MNQ")
  })
})
