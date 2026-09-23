import type { ReconstructionFill } from "./tradeReconstruction.ts"

/** Production broker account scope (Tradovate external_account_id). */
export const TRADOVATE_PERFORMANCE_FIXTURE_ACCOUNT_SCOPE = "65788591"

export const MGC_CONTRACT_ID = "4176766"
export const MNQ_CONTRACT_U6 = "4399654"
export const MNQ_CONTRACT_Z6 = "4470324"

function f(
  fillId: string,
  contractId: string,
  action: "Buy" | "Sell",
  qty: number,
  price: number,
  timestamp: string
): ReconstructionFill {
  return { fillId, contractId, action, qty, price, timestamp }
}

/**
 * Authoritative Tradovate Performance export (Sep 2026) — ledger fills from production
 * plus the three MGC fills that were dropped before order-account hydration (660290950326/296/290).
 * Prices for the missing fills match Performance P&L +28 / +32 (MGC $10/point).
 */
export function tradovatePerformanceSep2026ReconstructionFills(): ReconstructionFill[] {
  return [
    // MGC lifecycle 1 (-3)
    f("660290950163", MGC_CONTRACT_ID, "Buy", 1, 4348.4, "2026-09-17T20:11:25.498Z"),
    f("660290950170", MGC_CONTRACT_ID, "Sell", 1, 4348.1, "2026-09-17T20:11:40.600Z"),
    // MGC Sep 22 (-5)
    f("660290950232", MGC_CONTRACT_ID, "Buy", 1, 4343.2, "2026-09-22T17:17:00.229Z"),
    f("660290950240", MGC_CONTRACT_ID, "Sell", 1, 4342.7, "2026-09-22T17:17:09.354Z"),
    // MGC (+1)
    f("660290950248", MGC_CONTRACT_ID, "Sell", 1, 4342.5, "2026-09-22T17:22:08.401Z"),
    f("660290950254", MGC_CONTRACT_ID, "Buy", 1, 4342.4, "2026-09-22T17:22:39.006Z"),
    // MGC short 2-lot (-26 and -18 in Performance → one -44 lifecycle)
    f("660290950262", MGC_CONTRACT_ID, "Sell", 1, 4359.9, "2026-09-22T18:24:31.567Z"),
    f("660290950268", MGC_CONTRACT_ID, "Sell", 1, 4359.1, "2026-09-22T18:25:07.490Z"),
    f("660290950280", MGC_CONTRACT_ID, "Buy", 2, 4361.7, "2026-09-22T18:26:42.387Z"),
    // MGC long 2-lot scale-out (+28 + +32 → +60); missing from ledger before order hydration fix
    f("660290950326", MGC_CONTRACT_ID, "Buy", 2, 4358.7, "2026-09-22T18:36:27.000Z"),
    f("660290950296", MGC_CONTRACT_ID, "Sell", 1, 4361.5, "2026-09-22T18:36:43.000Z"),
    f("660290950290", MGC_CONTRACT_ID, "Sell", 1, 4361.9, "2026-09-22T18:38:30.000Z"),
    // MGC Sep 23 (-4)
    f("660290950341", MGC_CONTRACT_ID, "Sell", 2, 4362.1, "2026-09-23T00:48:10.221Z"),
    f("660290950347", MGC_CONTRACT_ID, "Buy", 2, 4362.3, "2026-09-23T00:48:48.617Z"),

    // MNQU6 (-11.50 total across lifecycles in export window)
    f("660290950007", MNQ_CONTRACT_U6, "Buy", 1, 29162.75, "2026-09-14T23:35:06.932Z"),
    f("660290950014", MNQ_CONTRACT_U6, "Buy", 1, 29162.75, "2026-09-14T23:36:38.698Z"),
    f("660290950020", MNQ_CONTRACT_U6, "Buy", 1, 29163, "2026-09-14T23:36:40.633Z"),
    f("660290950026", MNQ_CONTRACT_U6, "Buy", 1, 29163, "2026-09-14T23:36:42.276Z"),
    f("660290950032", MNQ_CONTRACT_U6, "Buy", 1, 29163, "2026-09-14T23:36:43.357Z"),
    f("660290950038", MNQ_CONTRACT_U6, "Sell", 5, 29161.75, "2026-09-14T23:37:08.527Z"),
    f("660290950054", MNQ_CONTRACT_U6, "Buy", 1, 29165.75, "2026-09-15T00:08:52.738Z"),
    f("660290950072", MNQ_CONTRACT_U6, "Sell", 1, 29160.25, "2026-09-15T00:10:22.486Z"),
    f("660290950080", MNQ_CONTRACT_U6, "Sell", 1, 29011, "2026-09-15T14:34:18.184Z"),
    f("660290950086", MNQ_CONTRACT_U6, "Buy", 1, 29000, "2026-09-15T14:39:59.855Z"),
    f("660290950094", MNQ_CONTRACT_U6, "Buy", 1, 28993.25, "2026-09-15T15:46:21.836Z"),
    f("660290950100", MNQ_CONTRACT_U6, "Sell", 1, 28987.75, "2026-09-15T15:46:52.606Z"),

    // MNQZ6 (-33.50)
    f("660290950127", MNQ_CONTRACT_Z6, "Buy", 1, 29743.25, "2026-09-17T17:47:21.429Z"),
    f("660290950135", MNQ_CONTRACT_Z6, "Buy", 1, 29743.25, "2026-09-17T17:47:37.854Z"),
    f("660290950141", MNQ_CONTRACT_Z6, "Buy", 1, 29743.5, "2026-09-17T17:47:38.042Z"),
    f("660290950147", MNQ_CONTRACT_Z6, "Sell", 3, 29740.5, "2026-09-17T17:48:11.230Z"),
    f("660290950178", MNQ_CONTRACT_Z6, "Buy", 1, 29716, "2026-09-17T20:29:57.177Z"),
    f("660290950184", MNQ_CONTRACT_Z6, "Buy", 1, 29716.75, "2026-09-17T20:30:05.022Z"),
    f("660290950190", MNQ_CONTRACT_Z6, "Buy", 1, 29716.75, "2026-09-17T20:30:05.224Z"),
    f("660290950196", MNQ_CONTRACT_Z6, "Buy", 1, 29716.75, "2026-09-17T20:30:05.407Z"),
    f("660290950202", MNQ_CONTRACT_Z6, "Sell", 1, 29714.5, "2026-09-17T20:30:22.901Z"),
    f("660290950210", MNQ_CONTRACT_Z6, "Sell", 3, 29714.5, "2026-09-17T20:30:25.224Z"),
  ]
}

/** MGC fills as persisted before the missing long round-trip (production-shaped gap). */
export function tradovateMgcFillsMissingProfitableRoundTrip(): ReconstructionFill[] {
  return tradovatePerformanceSep2026ReconstructionFills().filter(
    (row) =>
      row.contractId === MGC_CONTRACT_ID &&
      !["660290950326", "660290950296", "660290950290"].includes(row.fillId)
  )
}
