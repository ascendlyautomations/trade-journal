import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { mergeBrokerTradeFinancialFields } from "./brokerTradeAuthoritativeMerge.ts"
import {
  mergeTradovateContractMetaMaps,
  mergeTradovateExecutionMetadataFields,
  resolveBrokerTradeTicker,
  isValidResolvedTradovateSymbol,
} from "./tradovateContractMeta.ts"
import {
  buildTradovateContractMetadataSnapshot,
  mergeTradovateContractMetadataSnapshots,
  executionHintToMetadataSnapshot,
  brokerContractMetaFromSnapshot,
  unresolvedTradovateContractSnapshot,
} from "./tradovateContractResolutionCore.ts"
import {
  resolveEffectiveValuePerPoint,
  resolveEffectiveValuePerPointSource,
} from "./futuresValuePerPointFallback.ts"
import { computeTradovateBrokerTradeFinancials } from "./tradovateBrokerTradeFinancials.ts"
import {
  MGC_CONTRACT_ID,
  MNQ_CONTRACT_U6,
  MNQ_CONTRACT_Z6,
  TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE,
  tradovatePerformanceSep2026ReconstructionFills,
} from "./tradovatePerformanceSep2026Fixture.ts"
import {
  reconstructAllCompletedTrades,
  type ReconstructedLifecycleTrade,
} from "./tradeReconstruction.ts"

function productSnapshot(contractId: string, productName: string, vpp: number) {
  return buildTradovateContractMetadataSnapshot({
    contract: { id: contractId, name: `${productName}U6`, contractMaturityId: "1" },
    maturity: { id: "1", productId: "99" },
    product: { id: "99", name: productName, valuePerPoint: vpp },
  })
}

describe("Tradovate contract resolution v2", () => {
  it("A: contractId 4399654 resolves to MNQ via Product.name", () => {
    const snap = productSnapshot(MNQ_CONTRACT_U6, "MNQ", 2)
    assert.equal(snap.symbolRoot, "MNQ")
    assert.equal(snap.metadataQuality, "RESOLVED_PRODUCT")
    assert.equal(snap.valuePerPoint, 2)
    const ticker = resolveBrokerTradeTicker({
      contract: brokerContractMetaFromSnapshot(snap),
      contractId: MNQ_CONTRACT_U6,
    })
    assert.equal(ticker, "MNQ")
  })

  it("B: contractId 4470324 resolves to MNQ", () => {
    const snap = productSnapshot(MNQ_CONTRACT_Z6, "MNQ", 2)
    assert.equal(snap.symbolRoot, "MNQ")
    assert.equal(
      resolveBrokerTradeTicker({
        contract: brokerContractMetaFromSnapshot(snap),
        contractId: MNQ_CONTRACT_Z6,
      }),
      "MNQ"
    )
  })

  it("C: MGC contractId 4176766 resolves correctly", () => {
    const snap = productSnapshot(MGC_CONTRACT_ID, "MGC", 10)
    assert.equal(snap.symbolRoot, "MGC")
    assert.equal(snap.valuePerPoint, 10)
  })

  it("D: Product.valuePerPoint preferred over local fallback", () => {
    const source = resolveEffectiveValuePerPointSource({
      symbolRoot: "MNQ",
      contractValuePerPoint: 2,
    })
    assert.equal(source, "product")
    assert.equal(
      resolveEffectiveValuePerPoint({ symbolRoot: "MNQ", contractValuePerPoint: 2 }),
      2
    )
    const localOnly = resolveEffectiveValuePerPointSource({
      symbolRoot: "MNQ",
      contractValuePerPoint: null,
    })
    assert.equal(localOnly, "local_fallback")
  })

  it("E: numeric contractId can NEVER become final trades.ticker", () => {
    assert.equal(isValidResolvedTradovateSymbol("4399654"), false)
    assert.equal(
      resolveBrokerTradeTicker({
        contract: { symbolRoot: "4399654", contractName: "" },
        contractId: "4399654",
      }),
      ""
    )
    assert.equal(
      resolveBrokerTradeTicker({
        contract: null,
        contractId: "4176766",
      }),
      ""
    )
  })

  it("F: product resolution failure preserves existing valid ticker/VPP on execution ledger", () => {
    const merged = mergeTradovateExecutionMetadataFields(
      {
        symbol_root: "MNQ",
        contract_name: "MNQU6",
        value_per_point: 2,
        metadata_quality: "PERSISTED_VALID_HINT",
      },
      {
        symbol_root: "4399654",
        contract_name: null,
        value_per_point: null,
        metadata_quality: "UNRESOLVED",
      }
    )
    assert.equal(merged.symbol_root, "MNQ")
    assert.equal(merged.contract_name, "MNQU6")
    assert.equal(merged.value_per_point, 2)
    assert.equal(merged.numericTickerPrevented, true)
  })

  it("G: incoming pnl=null cannot overwrite existing valid P&L when metadata failed", () => {
    const merged = mergeBrokerTradeFinancialFields({
      existingPnL: -17,
      existingTicker: "MNQ",
      incomingPnL: null,
      incomingTicker: "",
    })
    assert.equal(merged.finalPnL, -17)
    assert.equal(merged.finalTicker, "MNQ")
  })

  it("H: repeated resync does not downgrade metadata quality", () => {
    const first = executionHintToMetadataSnapshot({
      external_contract_id: MNQ_CONTRACT_U6,
      symbol_root: "MNQ",
      contract_name: "MNQU6",
      value_per_point: 2,
      metadata_quality: "PERSISTED_VALID_HINT",
    })!
    const failedRest = mergeTradovateContractMetadataSnapshots(first, {
      contractId: MNQ_CONTRACT_U6,
      contractName: null,
      contractMaturityId: null,
      productId: null,
      productName: null,
      symbolRoot: null,
      valuePerPoint: null,
      tickSize: null,
      metadataQuality: "UNRESOLVED",
      resolutionStage: "product",
      unresolvedReason: "product_fetch_failed",
    })
    assert.equal(failedRest.symbolRoot, "MNQ")
    assert.equal(failedRest.valuePerPoint, 2)
  })

  it("I: later successful resolution upgrades previously unresolved execution", () => {
    const unresolved = unresolvedTradovateContractSnapshot(MNQ_CONTRACT_U6)
    const upgraded = mergeTradovateContractMetadataSnapshots(
      unresolved,
      productSnapshot(MNQ_CONTRACT_U6, "MNQ", 2)
    )
    assert.equal(upgraded.symbolRoot, "MNQ")
    assert.equal(upgraded.valuePerPoint, 2)
    assert.equal(upgraded.metadataQuality, "RESOLVED_PRODUCT")
  })

  it("J: Phase 1 Performance fixture still MNQ -45, MGC +5, overall -40, 12 lifecycles", () => {
    const fills = tradovatePerformanceSep2026ReconstructionFills()
    const { completed } = reconstructAllCompletedTrades(
      fills,
      TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE
    )
    assert.equal(completed.length, 12)

    const contracts = mergeTradovateContractMetaMaps(
      new Map([
        [MNQ_CONTRACT_U6, { contractId: MNQ_CONTRACT_U6, contractName: "MNQU6", symbolRoot: "MNQ", valuePerPoint: 2 }],
        [MNQ_CONTRACT_Z6, { contractId: MNQ_CONTRACT_Z6, contractName: "MNQZ6", symbolRoot: "MNQ", valuePerPoint: 2 }],
        [MGC_CONTRACT_ID, { contractId: MGC_CONTRACT_ID, contractName: "MGCV6", symbolRoot: "MGC", valuePerPoint: 10 }],
      ]),
      []
    )

    function sumNet(trades: ReconstructedLifecycleTrade[], contractId: string): number {
      let t = 0
      for (const lifecycle of trades.filter((x) => x.contractId === contractId)) {
        const fin = computeTradovateBrokerTradeFinancials({
          lifecycle,
          contract: contracts.get(contractId),
          contractIdKey: contractId,
          feesByFillId: new Map(),
        })
        assert.notEqual(fin.netPnL, null)
        t += fin.netPnL!
      }
      return t
    }

    const mgc = sumNet(completed, MGC_CONTRACT_ID)
    const mnqU = sumNet(completed.filter((t) => t.contractId === MNQ_CONTRACT_U6), MNQ_CONTRACT_U6)
    const mnqZ = sumNet(completed.filter((t) => t.contractId === MNQ_CONTRACT_Z6), MNQ_CONTRACT_Z6)
    assert.ok(Math.abs(mgc - 5) < 0.01)
    assert.ok(Math.abs(mnqU + mnqZ + 45) < 0.01)
    assert.ok(Math.abs(mgc + mnqU + mnqZ + 40) < 0.01)
  })
})
