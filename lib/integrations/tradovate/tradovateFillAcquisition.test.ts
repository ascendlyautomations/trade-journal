import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { computeTradovateBrokerTradeFinancials } from "./tradovateBrokerTradeFinancials.ts"
import {
  dedupeTradovateFillsById,
  mergeAccountScopedTradovateFills,
  tradovateLdepsBatchCount,
  TRADOVATE_LDEPS_BATCH_SIZE,
} from "./tradovateFillAcquisitionCore.ts"
import {
  MGC_CONTRACT_ID,
  MNQ_CONTRACT_U6,
  MNQ_CONTRACT_Z6,
  TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE,
  tradovatePerformanceSep2026ReconstructionFills,
} from "./tradovatePerformanceSep2026Fixture.ts"
import {
  buildTradovateOrderAccountMap,
  filterParsedTradovateFillsForAccount,
} from "./tradovateOrderAccountMap.ts"
import {
  reconstructAllCompletedTrades,
  type ReconstructedLifecycleTrade,
  type ReconstructionFill,
} from "./tradeReconstruction.ts"
import { TRACED_MGC_FILL_IDS } from "./tradovateFillTrace.ts"
import type { TradovateFillRaw } from "./tradovateFillModels.ts"

const OTHER_ACCOUNT = "99999999"

function toRaw(
  fill: ReconstructionFill,
  orderId: string
): TradovateFillRaw {
  return {
    id: fill.fillId,
    orderId,
    contractId: fill.contractId,
    timestamp: fill.timestamp,
    action: fill.action,
    qty: fill.qty,
    price: fill.price,
  }
}

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
    assert.notEqual(fin.netPnL, null)
    total += fin.netPnL!
  }
  return total
}

describe("tradovateFillAcquisition v2", () => {
  it("dedupes fills by Tradovate fill.id (last row wins)", () => {
    const a: TradovateFillRaw = {
      id: "1",
      orderId: "10",
      contractId: MGC_CONTRACT_ID,
      timestamp: "2026-01-01T00:00:00.000Z",
      action: "Buy",
      qty: 1,
      price: 100,
    }
    const b: TradovateFillRaw = { ...a, price: 200 }
    const deduped = dedupeTradovateFillsById([a, b])
    assert.equal(deduped.length, 1)
    assert.equal(deduped[0]!.price, 200)
    assert.deepEqual(dedupeTradovateFillsById(deduped), deduped)
  })

  it("chunks fill/ldeps order ids in batches of 40", () => {
    assert.equal(tradovateLdepsBatchCount(0), 0)
    assert.equal(tradovateLdepsBatchCount(1), 1)
    assert.equal(tradovateLdepsBatchCount(TRADOVATE_LDEPS_BATCH_SIZE), 1)
    assert.equal(tradovateLdepsBatchCount(TRADOVATE_LDEPS_BATCH_SIZE + 1), 2)
    assert.equal(tradovateLdepsBatchCount(85), 3)
  })

  it("order/deps path fills are account-scoped; supplemental fill/list is filtered", () => {
    const orderAccountById = buildTradovateOrderAccountMap([
      { id: 100, accountId: Number(TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE) },
      { id: 200, accountId: Number(OTHER_ACCOUNT) },
    ])

    const primary: TradovateFillRaw[] = [
      {
        id: "660290950326",
        orderId: "100",
        contractId: MGC_CONTRACT_ID,
        timestamp: "2026-09-22T18:36:27.000Z",
        action: "Buy",
        qty: 2,
        price: 4358.7,
      },
    ]

    const supplemental: TradovateFillRaw[] = [
      ...primary,
      {
        id: "660290950999",
        orderId: "200",
        contractId: MGC_CONTRACT_ID,
        timestamp: "2026-09-22T19:00:00.000Z",
        action: "Sell",
        qty: 1,
        price: 1,
      },
    ]

    const merged = mergeAccountScopedTradovateFills({
      primaryFills: primary,
      supplementalFills: supplemental,
      targetAccountId: TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE,
      orderAccountById,
    })

    assert.equal(merged.length, 1)
    assert.equal(String(merged[0]!.id), "660290950326")
  })

  it("merges ldeps-only MGC fills with fill/list supplemental without duplicates", () => {
    const fixture = tradovatePerformanceSep2026ReconstructionFills()
    const traced = new Set(TRACED_MGC_FILL_IDS)
    let orderSeq = 900000
    const allRaw = fixture.map((f) => toRaw(f, String(orderSeq++)))

    const primary = allRaw.filter((f) => traced.has(String(f.id)))
    const supplemental = allRaw.filter((f) => !traced.has(String(f.id)))

    assert.equal(primary.length, 3)
    assert.ok(supplemental.length > primary.length)

    const orderAccountById = buildTradovateOrderAccountMap([])
    for (const fill of allRaw) {
      if (fill.orderId != null) {
        orderAccountById.set(String(fill.orderId), TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE)
      }
    }

    const merged = mergeAccountScopedTradovateFills({
      primaryFills: primary,
      supplementalFills: supplemental,
      targetAccountId: TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE,
      orderAccountById,
    })

    assert.equal(merged.length, fixture.length)
    for (const id of TRACED_MGC_FILL_IDS) {
      assert.ok(
        merged.some((f) => String(f.id) === id),
        `expected fill ${id} in merged acquisition set`
      )
    }
  })

  it("partial acquisition: empty supplemental still retains primary ldeps fills", () => {
    const orderAccountById = buildTradovateOrderAccountMap([])
    orderAccountById.set("1", TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE)
    const primary: TradovateFillRaw[] = [
      {
        id: "660290950326",
        orderId: "1",
        contractId: MGC_CONTRACT_ID,
        timestamp: "2026-09-22T18:36:27.000Z",
        action: "Buy",
        qty: 2,
        price: 4358.7,
      },
    ]
    const merged = mergeAccountScopedTradovateFills({
      primaryFills: primary,
      supplementalFills: [],
      targetAccountId: TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE,
      orderAccountById,
    })
    assert.equal(merged.length, 1)
  })

  it("v2 merged fixture reaches MNQ -45, MGC +5, overall -40, 12 lifecycles", () => {
    const fixture = tradovatePerformanceSep2026ReconstructionFills()
    const traced = new Set(TRACED_MGC_FILL_IDS)
    let orderSeq = 900000
    const allRaw = fixture.map((f) => toRaw(f, String(orderSeq++)))
    const primary = allRaw.filter((f) => traced.has(String(f.id)))
    const supplemental = allRaw.filter((f) => !traced.has(String(f.id)))

    const orderAccountById = buildTradovateOrderAccountMap([])
    for (const fill of allRaw) {
      if (fill.orderId != null) {
        orderAccountById.set(String(fill.orderId), TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE)
      }
    }

    const merged = mergeAccountScopedTradovateFills({
      primaryFills: primary,
      supplementalFills: supplemental,
      targetAccountId: TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE,
      orderAccountById,
    })

    const reconstructionFills: ReconstructionFill[] = merged.map((f) => ({
      fillId: String(f.id),
      contractId: String(f.contractId),
      action: f.action as "Buy" | "Sell",
      qty: Number(f.qty),
      price: Number(f.price),
      timestamp: String(f.timestamp),
    }))

    const { completed } = reconstructAllCompletedTrades(
      reconstructionFills,
      TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE
    )
    assert.equal(completed.length, 12)

    const mgcTotal = sumNetPnL(completed, MGC_CONTRACT_ID)
    assert.ok(Math.abs(mgcTotal - 5) < 0.01, `MGC expected +5 got ${mgcTotal}`)

    const mnqUTotal = sumNetPnL(
      completed.filter((t) => t.contractId === MNQ_CONTRACT_U6),
      MNQ_CONTRACT_U6
    )
    const mnqZTotal = sumNetPnL(
      completed.filter((t) => t.contractId === MNQ_CONTRACT_Z6),
      MNQ_CONTRACT_Z6
    )
    assert.ok(Math.abs(mnqUTotal + mnqZTotal + 45) < 0.01)
    assert.ok(Math.abs(mgcTotal + mnqUTotal + mnqZTotal + 40) < 0.01)
  })

  it("supplemental-only account filter excludes fills without order account mapping", () => {
    const fills: TradovateFillRaw[] = [
      {
        id: "1",
        orderId: "77",
        contractId: MGC_CONTRACT_ID,
        timestamp: "2026-01-01T00:00:00.000Z",
        action: "Buy",
        qty: 1,
        price: 1,
      },
    ]
    const scoped = filterParsedTradovateFillsForAccount(
      fills,
      TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE,
      new Map()
    )
    assert.equal(scoped.length, 0)
  })
})
