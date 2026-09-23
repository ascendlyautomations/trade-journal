import {
  MGC_CONTRACT_ID,
  MNQ_CONTRACT_U6,
  MNQ_CONTRACT_Z6,
} from "./tradovatePerformanceSep2026Fixture.ts"
import type { NormalizedTradovateFillPair } from "./tradovateFillPairModels.ts"
import type { TradovateLedgerFillContext } from "./tradovateFillPairCore.ts"

function pair(
  id: string,
  buyFillId: string,
  sellFillId: string,
  qty: number,
  buyPrice: number,
  sellPrice: number
): NormalizedTradovateFillPair {
  return {
    id,
    positionId: "pos-fixture",
    buyFillId,
    sellFillId,
    qty,
    buyPrice,
    sellPrice,
    active: true,
  }
}

/** Performance-shaped FillPair rows for Sep 2026 validation fixture (gross P&L). */
export function tradovatePerformanceSep2026FillPairs(): NormalizedTradovateFillPair[] {
  return [
    // MGC short scale-out as two FIFO pairs (-26, -18) vs lifecycle -44
    pair("fp-mgc-1", "660290950280", "660290950268", 1, 4361.7, 4359.1),
    pair("fp-mgc-2", "660290950280", "660290950262", 1, 4361.7, 4359.9),
    // MGC profitable long scale-out (+28, +32) = +60 lifecycle
    pair("fp-mgc-3", "660290950326", "660290950296", 1, 4358.7, 4361.5),
    pair("fp-mgc-4", "660290950326", "660290950290", 1, 4358.7, 4361.9),
    // Representative MNQ pairs (totals reconcile at account level in full fixture)
    pair("fp-mnq-1", "660290950007", "660290950038", 1, 29162.75, 29161.75),
    pair("fp-mnq-2", "660290950127", "660290950147", 1, 29743.25, 29740.5),
  ]
}

export function tradovatePerformanceSep2026FillContexts(): Map<
  string,
  TradovateLedgerFillContext
> {
  const rows: TradovateLedgerFillContext[] = [
    { fillId: "660290950262", contractId: MGC_CONTRACT_ID, tradeDate: "2026-09-22" },
    { fillId: "660290950268", contractId: MGC_CONTRACT_ID, tradeDate: "2026-09-22" },
    { fillId: "660290950280", contractId: MGC_CONTRACT_ID, tradeDate: "2026-09-22" },
    { fillId: "660290950326", contractId: MGC_CONTRACT_ID, tradeDate: "2026-09-22" },
    { fillId: "660290950296", contractId: MGC_CONTRACT_ID, tradeDate: "2026-09-22" },
    { fillId: "660290950290", contractId: MGC_CONTRACT_ID, tradeDate: "2026-09-22" },
    { fillId: "660290950007", contractId: MNQ_CONTRACT_U6, tradeDate: "2026-09-14" },
    { fillId: "660290950038", contractId: MNQ_CONTRACT_U6, tradeDate: "2026-09-14" },
    { fillId: "660290950127", contractId: MNQ_CONTRACT_Z6, tradeDate: "2026-09-17" },
    { fillId: "660290950147", contractId: MNQ_CONTRACT_Z6, tradeDate: "2026-09-17" },
  ]
  return new Map(rows.map((r) => [r.fillId, r]))
}
