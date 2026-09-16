/** Server-side phase timings for Rithmic connect (no credentials). */
export type RithmicConnectTimingMark = {
  phase: string
  elapsedMs: number
}

const marks: RithmicConnectTimingMark[] = []
let startedAt = 0

export function resetRithmicConnectTiming(): void {
  marks.length = 0
  startedAt = Date.now()
}

export function markRithmicConnectPhase(phase: string): void {
  if (!startedAt) startedAt = Date.now()
  marks.push({ phase, elapsedMs: Date.now() - startedAt })
}

export function flushRithmicConnectTiming(): RithmicConnectTimingMark[] {
  return [...marks]
}

export function logRithmicConnectTiming(outcome: string): void {
  const summary = marks.map((m) => `${m.phase}@${m.elapsedMs}ms`).join(" ")
  console.info(
    "[rithmic/connect/timing]",
    JSON.stringify({ outcome, totalMs: Date.now() - startedAt, phases: summary })
  )
}
