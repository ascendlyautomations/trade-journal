import type { PsychologyCoachSummary } from "./reports/coach.ts"
import type { PsychologyAnalyticsReport, PsychologyCoachFacts } from "./reports/types.ts"

export type { PsychologyCoachSummary }

type PsychologySession = {
  report: PsychologyAnalyticsReport | null
  facts: PsychologyCoachFacts | null
  summary: PsychologyCoachSummary | null
  highlightedSectionID: string | null
}

let session: PsychologySession = {
  report: null,
  facts: null,
  summary: null,
  highlightedSectionID: null,
}

export function setPsychologySession(update: {
  report?: PsychologyAnalyticsReport | null
  facts?: PsychologyCoachFacts | null
  summary?: PsychologyCoachSummary | null
}): void {
  if (update.report !== undefined) session.report = update.report
  if (update.facts !== undefined) session.facts = update.facts
  if (update.summary !== undefined) session.summary = update.summary
}

export function focusPsychologySection(sectionID: string | null): void {
  session.highlightedSectionID = sectionID
}

export function getPsychologySession(): PsychologySession {
  return session
}

export function clearPsychologySession(): void {
  session = {
    report: null,
    facts: null,
    summary: null,
    highlightedSectionID: null,
  }
}
