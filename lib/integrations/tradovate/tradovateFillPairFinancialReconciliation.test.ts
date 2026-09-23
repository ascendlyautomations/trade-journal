import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { computeTradovateBrokerTradeFinancials } from "./tradovateBrokerTradeFinancials.ts"
import {
  mergeTradovateFillFeeMaps,
  mergeTradovateFillFeeRecords,
  type TradovateFillFeeRecord,
} from "./tradovateFillFeeCoverageCore.ts"
import { mergeTradovateProviderMetadataFeeFields } from "./tradovateExecutionProviderMetadata.ts"
import { normalizeTradovateFillPairRow } from "./tradovateFillPairModels.ts"
import { computeTradovateFillPairGrossPnl } from "./tradovateFillPairCore.ts"
import {
  lifecycleGrossPnl,
  reconcileTradovateFinancials,
} from "./tradovateFinancialReconciliationCore.ts"
import {
  MGC_CONTRACT_ID,
  MNQ_CONTRACT_U6,
  MNQ_CONTRACT_Z6,
  TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE,
  tradovatePerformanceSep2026ReconstructionFills,
} from "./tradovatePerformanceSep2026Fixture.ts"
import {
  tradovatePerformanceSep2026FillContexts,
  tradovatePerformanceSep2026FillPairs,
} from "./tradovatePerformanceSep2026FillPairs.ts"
import {
  reconstructAllCompletedTrades,
  type ReconstructedLifecycleTrade,
} from "./tradeReconstruction.ts"
import type { BrokerContractMeta } from "./tradovateContractMeta.ts"

const MGC_META: BrokerContractMeta = {
  symbolRoot: "MGC",
  contractName: "MGCV6",
  valuePerPoint: 10,
}

const MNQ_META: BrokerContractMeta = {
  symbolRoot: "MNQ",
  contractName: "MNQU6",
  valuePerPoint: 2,
}

function contractsMap(): Map<string, BrokerContractMeta> {
  return new Map([
    [MGC_CONTRACT_ID, MGC_META],
    [MNQ_CONTRACT_U6, MNQ_META],
    [MNQ_CONTRACT_Z6, { ...MNQ_META, contractName: "MNQZ6" }],
  ])
}

describe("Tradovate FillPair validation + fee coverage", () => {
  it("A: FillPair normalization", () => {
    const normalized = normalizeTradovateFillPairRow({
      id: 1,
      positionId: 9,
      buyFillId: 100,
      sellFillId: 101,
      qty: 2,
      buyPrice: 100,
      sellPrice: 101,
      active: true,
    })
    assert.ok(normalized)
    assert.equal(normalized!.buyFillId, "100")
    assert.equal(normalized!.qty, 2)
  })

  it("B: FIFO pair rows -26 + -18 reconcile to one -44 lifecycle", () => {
    const pairs = tradovatePerformanceSep2026FillPairs().filter((p) =>
      p.id.startsWith("fp-mgc-1") || p.id.startsWith("fp-mgc-2")
    )
    const fillsById = tradovatePerformanceSep2026FillContexts()
    let pairTotal = 0
    for (const pair of pairs) {
      const { grossPnl } = computeTradovateFillPairGrossPnl({
        pair,
        contract: MGC_META,
        contractId: MGC_CONTRACT_ID,
      })
      assert.notEqual(grossPnl, null)
      pairTotal += grossPnl!
    }
    assert.ok(Math.abs(pairTotal + 44) < 0.01)

    const { completed } = reconstructAllCompletedTrades(
      tradovatePerformanceSep2026ReconstructionFills(),
      TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE
    )
    const shortLifecycle = completed.find((t) => t.fillIds.includes("660290950280"))
    assert.ok(shortLifecycle)
    const { grossPnl } = lifecycleGrossPnl(shortLifecycle!, MGC_META)
    assert.ok(Math.abs((grossPnl ?? 0) + 44) < 0.01)
    assert.ok(Math.abs(pairTotal - (grossPnl ?? 0)) < 0.01)
  })

  it("C: +28 + +32 pair rows reconcile to +60 lifecycle", () => {
    const pairs = tradovatePerformanceSep2026FillPairs().filter((p) =>
      p.id.startsWith("fp-mgc-3") || p.id.startsWith("fp-mgc-4")
    )
    let pairTotal = 0
    for (const pair of pairs) {
      const { grossPnl } = computeTradovateFillPairGrossPnl({
        pair,
        contract: MGC_META,
        contractId: MGC_CONTRACT_ID,
      })
      pairTotal += grossPnl ?? 0
    }
    assert.ok(Math.abs(pairTotal - 60) < 0.01)

    const { completed } = reconstructAllCompletedTrades(
      tradovatePerformanceSep2026ReconstructionFills(),
      TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE
    )
    const winner = completed.find((t) => t.fillIds.includes("660290950326"))
    assert.ok(winner)
    const { grossPnl } = lifecycleGrossPnl(winner!, MGC_META)
    assert.ok(Math.abs((grossPnl ?? 0) - 60) < 0.01)
  })

  it("D: Performance fixture lifecycle gross MNQ -45, MGC +5, overall -40", () => {
    const { completed } = reconstructAllCompletedTrades(
      tradovatePerformanceSep2026ReconstructionFills(),
      TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE
    )
    const contracts = contractsMap()
    function sumGross(filter: (t: ReconstructedLifecycleTrade) => boolean): number {
      let t = 0
      for (const lifecycle of completed.filter(filter)) {
        const { grossPnl } = lifecycleGrossPnl(
          lifecycle,
          contracts.get(String(lifecycle.contractId))
        )
        t += grossPnl ?? 0
      }
      return t
    }
    const mgc = sumGross((t) => t.contractId === MGC_CONTRACT_ID)
    const mnq = sumGross(
      (t) => t.contractId === MNQ_CONTRACT_U6 || t.contractId === MNQ_CONTRACT_Z6
    )
    assert.ok(Math.abs(mgc - 5) < 0.01)
    assert.ok(Math.abs(mnq + 45) < 0.01)
    assert.ok(Math.abs(mgc + mnq + 40) < 0.01)
  })

  it("E: different FillPair count vs lifecycle count can still MATCH", () => {
    const { completed } = reconstructAllCompletedTrades(
      tradovatePerformanceSep2026ReconstructionFills(),
      TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE
    )
    const mgcShort = completed.filter((t) => t.fillIds.includes("660290950280"))
    const pairs = tradovatePerformanceSep2026FillPairs().filter((p) =>
      p.id.startsWith("fp-mgc-1") || p.id.startsWith("fp-mgc-2")
    )
    const result = reconcileTradovateFinancials({
      accountId: TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE,
      fillPairs: pairs,
      fillsById: tradovatePerformanceSep2026FillContexts(),
      completed: mgcShort,
      contracts: contractsMap(),
      insufficientFillPairData: false,
    })
    assert.equal(result.fillPairCount, 2)
    assert.equal(result.lifecycleCount, 1)
    assert.equal(result.status, "MATCH")
  })

  it("F: missing FillPair data returns INSUFFICIENT_FILLPAIR_DATA", () => {
    const { completed } = reconstructAllCompletedTrades(
      tradovatePerformanceSep2026ReconstructionFills(),
      TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE
    )
    const result = reconcileTradovateFinancials({
      accountId: TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE,
      fillPairs: [],
      fillsById: new Map(),
      completed,
      contracts: contractsMap(),
      insufficientFillPairData: true,
    })
    assert.equal(result.status, "INSUFFICIENT_FILLPAIR_DATA")
  })

  it("G: metadata failure returns UNRESOLVED_METADATA", () => {
    const pairs = tradovatePerformanceSep2026FillPairs().slice(0, 1)
    const result = reconcileTradovateFinancials({
      accountId: TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE,
      fillPairs: pairs,
      fillsById: tradovatePerformanceSep2026FillContexts(),
      completed: [],
      contracts: new Map(),
      insufficientFillPairData: false,
    })
    assert.equal(result.status, "UNRESOLVED_METADATA")
  })

  it("H: financial discrepancy returns MISMATCH with group diagnostics", () => {
    const pair = tradovatePerformanceSep2026FillPairs()[0]!
    const result = reconcileTradovateFinancials({
      accountId: TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE,
      fillPairs: [pair],
      fillsById: tradovatePerformanceSep2026FillContexts(),
      completed: [
        {
          lifecycleKey: "x",
          contractId: MGC_CONTRACT_ID,
          direction: "Short",
          contracts: 1,
          entryPrice: 1,
          exitPrice: 2,
          entryTime: "2026-09-22T18:00:00.000Z",
          exitTime: "2026-09-22T18:30:00.000Z",
          fillIds: ["660290950280"],
          points: -100,
        },
      ],
      contracts: contractsMap(),
      insufficientFillPairData: false,
    })
    assert.equal(result.status, "MISMATCH")
    assert.ok(result.groupDiagnostics.length >= 1)
  })

  it("I/J/K: fee batch merge, known fee survives failure, zero vs unavailable", () => {
    const persisted = new Map<string, TradovateFillFeeRecord>([
      [
        "1",
        {
          totals: { clearingFee: 1, exchangeFee: 0, nfaFee: 0, commission: 0 },
          availability: "KNOWN_VALUE",
        },
      ],
    ])
    const failedFetch = new Map<string, TradovateFillFeeRecord>([
      [
        "1",
        {
          totals: { clearingFee: 0, exchangeFee: 0, nfaFee: 0, commission: 0 },
          availability: "UNAVAILABLE",
        },
      ],
    ])
    const merged = mergeTradovateFillFeeMaps(persisted, failedFetch)
    assert.equal(merged.get("1")!.availability, "KNOWN_VALUE")
    assert.equal(merged.get("1")!.totals.clearingFee, 1)

    const zeroKnown: TradovateFillFeeRecord = {
      totals: { clearingFee: 0, exchangeFee: 0, nfaFee: 0, commission: 0 },
      availability: "KNOWN_ZERO",
    }
    assert.equal(mergeTradovateFillFeeRecords(null, zeroKnown).availability, "KNOWN_ZERO")
  })

  it("L: gross and net remain separate when fees unavailable", () => {
    const { completed } = reconstructAllCompletedTrades(
      tradovatePerformanceSep2026ReconstructionFills(),
      TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE
    )
    const lifecycle = completed.find((t) => t.fillIds.includes("660290950326"))!
    const fin = computeTradovateBrokerTradeFinancials({
      lifecycle,
      contract: MGC_META,
      contractIdKey: MGC_CONTRACT_ID,
      feesByFillId: new Map([
        [
          lifecycle.fillIds[0]!,
          {
            totals: { clearingFee: 0, exchangeFee: 0, nfaFee: 0, commission: 0 },
            availability: "UNAVAILABLE",
          },
        ],
      ]),
    })
    assert.notEqual(fin.grossPnL, null)
    assert.equal(fin.netPnL, null)
  })

  it("M: fee metadata merge is idempotent and non-degrading", () => {
    const known: TradovateFillFeeRecord = {
      totals: { clearingFee: 2, exchangeFee: 1, nfaFee: 0, commission: 0 },
      availability: "KNOWN_VALUE",
    }
    const first = mergeTradovateProviderMetadataFeeFields({}, known)
    const second = mergeTradovateProviderMetadataFeeFields(first, {
      totals: { clearingFee: 0, exchangeFee: 0, nfaFee: 0, commission: 0 },
      availability: "UNAVAILABLE",
    })
    const fees = second.tradovateFees as Record<string, unknown>
    assert.equal(fees.availability, "KNOWN_VALUE")
    assert.equal(fees.clearingFee, 2)
  })
})
