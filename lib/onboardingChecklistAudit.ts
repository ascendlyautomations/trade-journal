/** Temporary audit logging for onboarding checklist visibility (remove after verification). */

const PREFIX = "[onboarding-checklist-audit]"

export type OnboardingAuditProfileSnapshot = {
  userId: string | null
  onboarding_completed: boolean | null | undefined
  has_seen_getting_started_intro: boolean | null | undefined
  has_seen_onboarding_complete_popup: boolean | null | undefined
  profileLoading: boolean
  profileLoaded: boolean
}

export type OnboardingAuditSignalsSnapshot = {
  signalsReady: boolean
  onboardingCompleted: boolean
  hasSeenGettingStartedIntro: boolean
  hasSeenOnboardingCompletePopup: boolean
}

export type OnboardingAuditDecision = {
  source: string
  onboardingResolved: boolean
  onboardingCompleted: boolean
  renderChecklist: boolean
  reason: string
}

function log(label: string, payload: Record<string, unknown>) {
  if (typeof window === "undefined") return
  console.log(PREFIX, label, payload)
}

export function auditLogProfileLoaded(snapshot: OnboardingAuditProfileSnapshot) {
  log("profile loaded", snapshot)
}

export function auditLogSignalsResolved(
  snapshot: OnboardingAuditSignalsSnapshot & {
    userId: string | null
    preloadedFromProfile: boolean
  }
) {
  log("signals resolved", snapshot)
}

export function auditLogDashboardDecision(decision: OnboardingAuditDecision) {
  log("dashboard decision", decision)
}

export function auditLogDashboardMounted(userId: string | null) {
  log("dashboard mounted", { userId })
}
