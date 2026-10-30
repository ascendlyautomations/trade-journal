import type { PsychologyCoachSummary } from "./reports/coach.ts"
import type { PsychologyAnalyticsReport, PsychologyCoachFacts } from "./reports/types.ts"
import type { PsychologyAnalyticsScope } from "./psychologyScope.ts"

export type { PsychologyCoachSummary }

type PsychologySession = {
  report: PsychologyAnalyticsReport | null
  facts: PsychologyCoachFacts | null
  summary: PsychologyCoachSummary | null
  highlightedSectionID: string | null
  userId: string | null
  scopeFingerprint: string | null
  scopeLabel: string | null
}

let session: PsychologySession = {
  report: null,
  facts: null,
  summary: null,
  highlightedSectionID: null,
  userId: null,
  scopeFingerprint: null,
  scopeLabel: null,
}

let analyticsScope: PsychologyAnalyticsScope | null = null

export function setPsychologyAnalyticsScope(scope: PsychologyAnalyticsScope | null): void {
  analyticsScope = scope
}

export function getPsychologyAnalyticsScope(): PsychologyAnalyticsScope | null {
  return analyticsScope
}

export function setPsychologySession(update: {
  report?: PsychologyAnalyticsReport | null
  facts?: PsychologyCoachFacts | null
  summary?: PsychologyCoachSummary | null
  userId?: string | null
  scopeFingerprint?: string | null
  scopeLabel?: string | null
}): void {
  if (update.report !== undefined) session.report = update.report
  if (update.facts !== undefined) session.facts = update.facts
  if (update.summary !== undefined) session.summary = update.summary
  if (update.userId !== undefined) session.userId = update.userId
  if (update.scopeFingerprint !== undefined) {
    session.scopeFingerprint = update.scopeFingerprint
  }
  if (update.scopeLabel !== undefined) session.scopeLabel = update.scopeLabel
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
    userId: null,
    scopeFingerprint: null,
    scopeLabel: null,
  }
  analyticsScope = null
}
