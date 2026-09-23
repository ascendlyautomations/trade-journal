export type TradovateImportFlowLogPayload = {
  mode: string
  trigger: string
  mappingId: string
  persistCalled: boolean
  lifecyclesBuilt: number
  existingLifecycleCountAtStart: number
  previewEligibleCount: number
  importPreviewTradesCount: number
  inserted?: number
  updated?: number
  manualImportHoldActive?: boolean
  persistSkippedReason?: string
}

export function logTradovateImportFlow(payload: TradovateImportFlowLogPayload): void {
  const parts = [
    `[TradovateImportFlow] mode=${payload.mode}`,
    `trigger=${payload.trigger}`,
    `mappingId=${payload.mappingId}`,
    `lifecyclesBuilt=${payload.lifecyclesBuilt}`,
    `existingLifecycleCount=${payload.existingLifecycleCountAtStart}`,
    `previewEligibleCount=${payload.previewEligibleCount}`,
    `importPreviewTradesCount=${payload.importPreviewTradesCount}`,
    `persistCalled=${payload.persistCalled}`,
  ]
  if (payload.manualImportHoldActive != null) {
    parts.push(`manualImportHoldActive=${payload.manualImportHoldActive}`)
  }
  if (payload.persistSkippedReason) {
    parts.push(`persistSkippedReason=${payload.persistSkippedReason}`)
  }
  if (payload.inserted != null) parts.push(`inserted=${payload.inserted}`)
  if (payload.updated != null) parts.push(`updated=${payload.updated}`)
  console.info(parts.join(" "))
}
