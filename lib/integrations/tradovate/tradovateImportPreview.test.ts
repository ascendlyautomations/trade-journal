import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  buildTradovateImportPreviewTrades,
  type TradovateImportPreviewTrade,
} from "./tradovateImportPreview.ts"
import type { ReconstructedLifecycleTrade } from "./tradeReconstruction.ts"

const mnqShort: ReconstructedLifecycleTrade = {
  lifecycleKey: "tradovate:v2:65788591:4399654:3",
  contractId: "4399654",
  direction: "Short",
  contracts: 1,
  entryPrice: 29011,
  exitPrice: 29000,
  entryTime: "2026-09-01T14:00:00.000Z",
  exitTime: "2026-09-01T14:05:00.000Z",
  fillIds: ["f1", "f2"],
  points: 11,
}

function previewJson(trades: TradovateImportPreviewTrade[]): string {
  return JSON.stringify({ importPreviewTrades: trades })
}

describe("Tradovate import preview (review path)", () => {
  it("production-shaped MNQ short → ticker MNQ, points 11, pnl 22", () => {
    const previews = buildTradovateImportPreviewTrades({
      completed: [mnqShort],
      contracts: new Map([
        [
          "4399654",
          {
            symbolRoot: "4399654",
            executionSymbolRoot: "MNQ",
            executionContractName: "MNQU6",
            valuePerPoint: null,
          },
        ],
      ]),
      feesByFillId: new Map(),
    })
    assert.equal(previews.length, 1)
    assert.equal(previews[0]!.ticker, "MNQ")
    assert.equal(previews[0]!.points, 11)
    assert.equal(previews[0]!.pnl, 22)
    assert.equal(previews[0]!.grossPnl, 22)
    assert.equal(previews[0]!.fees, 0)
  })

  it("MNQ long loss multi-contract", () => {
    const lifecycle: ReconstructedLifecycleTrade = {
      ...mnqShort,
      direction: "Long",
      contracts: 2,
      entryPrice: 29000,
      exitPrice: 28989,
      points: -11,
    }
    const previews = buildTradovateImportPreviewTrades({
      completed: [lifecycle],
      contracts: new Map([
        ["4399654", { symbolRoot: "MNQ", valuePerPoint: 2 }],
      ]),
      feesByFillId: new Map(),
    })
    assert.equal(previews[0]!.pnl, -44)
  })

  it("MGC uses fallback multiplier", () => {
    const lifecycle: ReconstructedLifecycleTrade = {
      ...mnqShort,
      contractId: "4470324",
      lifecycleKey: "tradovate:v2:65788591:4470324:1",
      direction: "Long",
      entryPrice: 4480,
      exitPrice: 4481,
      points: 1,
      contracts: 1,
    }
    const previews = buildTradovateImportPreviewTrades({
      completed: [lifecycle],
      contracts: new Map([
        [
          "4470324",
          {
            symbolRoot: "4470324",
            executionSymbolRoot: "MGC",
            executionContractName: "MGCV6",
          },
        ],
      ]),
      feesByFillId: new Map(),
    })
    assert.equal(previews[0]!.ticker, "MGC")
    assert.equal(previews[0]!.pnl, 10)
  })

  it("missing REST contract metadata but execution symbol available", () => {
    const previews = buildTradovateImportPreviewTrades({
      completed: [mnqShort],
      contracts: new Map([
        [
          "4399654",
          {
            symbolRoot: "4399654",
            executionSymbolRoot: "MNQ",
            executionContractName: "MNQU6",
          },
        ],
      ]),
      feesByFillId: new Map(),
    })
    assert.equal(previews[0]!.ticker, "MNQ")
    assert.equal(previews[0]!.pnl, 22)
  })

  it("fees reduce net pnl when present", () => {
    const previews = buildTradovateImportPreviewTrades({
      completed: [mnqShort],
      contracts: new Map([["4399654", { symbolRoot: "MNQ", valuePerPoint: 2 }]]),
      feesByFillId: new Map([
        ["f1", { clearingFee: 0.5, exchangeFee: 0.25, nfaFee: 0, commission: 0.25 }],
        ["f2", { clearingFee: 0, exchangeFee: 0, nfaFee: 0, commission: 0 }],
      ]),
    })
    assert.equal(previews[0]!.grossPnl, 22)
    assert.equal(previews[0]!.fees, 1)
    assert.equal(previews[0]!.pnl, 21)
  })

  it("serialization boundary keeps pnl field", () => {
    const previews = buildTradovateImportPreviewTrades({
      completed: [mnqShort],
      contracts: new Map([["4399654", { symbolRoot: "MNQ", valuePerPoint: 2 }]]),
      feesByFillId: new Map(),
    })
    const parsed = JSON.parse(previewJson(previews)) as {
      importPreviewTrades: TradovateImportPreviewTrade[]
    }
    assert.equal(parsed.importPreviewTrades[0]!.pnl, 22)
    assert.equal(parsed.importPreviewTrades[0]!.ticker, "MNQ")
  })
})
