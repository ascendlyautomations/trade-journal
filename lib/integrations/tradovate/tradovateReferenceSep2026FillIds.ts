import { tradovatePerformanceSep2026ReconstructionFills } from "./tradovatePerformanceSep2026Fixture.ts"

export type TradovateReferenceSep2026FillIdAudit = {
  source: string
  uniqueFillIdCount: number
  fixtureRowCount: number
  fillIds: string[]
  byContractId: Record<string, { fillCount: number; fillIds: string[] }>
  notes: string[]
}

/** Reference Sep 14–23 fill IDs used by historical capability probes. */
export function tradovateReferenceSep2026FillIds(): string[] {
  return [
    ...new Set(
      tradovatePerformanceSep2026ReconstructionFills().map((f) => f.fillId)
    ),
  ]
}

export function auditTradovateReferenceSep2026FillIds(): TradovateReferenceSep2026FillIdAudit {
  const rows = tradovatePerformanceSep2026ReconstructionFills()
  const fillIds = tradovateReferenceSep2026FillIds()
  const byContractId: TradovateReferenceSep2026FillIdAudit["byContractId"] = {}

  for (const row of rows) {
    const bucket = byContractId[row.contractId] ?? { fillCount: 0, fillIds: [] }
    bucket.fillCount += 1
    bucket.fillIds.push(row.fillId)
    byContractId[row.contractId] = bucket
  }

  return {
    source:
      "tradovatePerformanceSep2026ReconstructionFills() in tradovatePerformanceSep2026Fixture.ts",
    uniqueFillIdCount: fillIds.length,
    fixtureRowCount: rows.length,
    fillIds,
    byContractId,
    notes: [
      "All IDs are authoritative Performance-export reconstruction fills for account 65788591 (Sep 2026 window).",
      "Includes three MGC fills (660290950326/296/290) added after the missing round-trip hydration fix.",
      "No IDs are copied from another TradeTraxs user ledger; they are fixture-derived reference IDs for probe matching.",
      fillIds.length === rows.length
        ? "Every fixture row has a distinct fillId."
        : "Some fixture rows share fillIds (unexpected).",
    ],
  }
}
