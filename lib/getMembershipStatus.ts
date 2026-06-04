export type MembershipStatus = "Trialing" | "Active" | "Canceling" | "Inactive"

function normalizeSubscriptionStatus(profile: unknown): string {
  if (!profile || typeof profile !== "object") return ""
  return String((profile as { subscription_status?: unknown }).subscription_status ?? "")
    .toLowerCase()
    .trim()
}

function parseProfileDate(raw: unknown): Date | null {
  if (raw == null || raw === "") return null
  const d = new Date(String(raw))
  return Number.isNaN(d.getTime()) ? null : d
}

function isCancelAtPeriodEnd(profile: unknown): boolean {
  if (!profile || typeof profile !== "object") return false
  return (profile as { cancel_at_period_end?: unknown }).cancel_at_period_end === true
}

function isTrialEndInFuture(profile: unknown, now = new Date()): boolean {
  if (!profile || typeof profile !== "object") return false
  const trialEnd = parseProfileDate(
    (profile as { trial_end?: unknown }).trial_end
  )
  return trialEnd != null && trialEnd > now
}

export function formatSubscriptionDateTime(raw: unknown): string {
  const d = parseProfileDate(raw)
  if (!d) return "—"
  return d.toLocaleString(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  })
}

export function shouldShowTrialInfo(profile: unknown): boolean {
  if (!profile) return false
  return normalizeSubscriptionStatus(profile) === "trialing" || isTrialEndInFuture(profile)
}

export function shouldShowRenewalInfo(profile: unknown): boolean {
  if (!profile) return false
  if (isCancelAtPeriodEnd(profile)) return false
  return normalizeSubscriptionStatus(profile) === "active"
}

export function shouldShowCancellationInfo(profile: unknown): boolean {
  return isCancelAtPeriodEnd(profile)
}

export function getMembershipStatus(profile: unknown): MembershipStatus {
  if (!profile) return "Inactive"

  if (isCancelAtPeriodEnd(profile)) {
    return "Canceling"
  }

  const status = normalizeSubscriptionStatus(profile)
  if (status === "trialing" || isTrialEndInFuture(profile)) {
    return "Trialing"
  }

  if (status === "active") {
    return "Active"
  }

  return "Inactive"
}
