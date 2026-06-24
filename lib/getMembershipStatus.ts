import { formatSubscriptionTimestamp, parseDateLike } from "@/lib/formatDate"

export type MembershipStatus = "Trialing" | "Active" | "Canceling" | "Inactive"

function normalizeSubscriptionStatus(profile: unknown): string {
  if (!profile || typeof profile !== "object") return ""
  return String((profile as { subscription_status?: unknown }).subscription_status ?? "")
    .toLowerCase()
    .trim()
}

function parseProfileDate(raw: unknown): Date | null {
  if (raw == null || raw === "") return null
  if (raw instanceof Date) {
    return Number.isNaN(raw.getTime()) ? null : raw
  }
  return parseDateLike(String(raw))
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

/** Viewer-local date + time with timezone abbreviation (trial_end, renewals, etc.). */
export function formatSubscriptionDateTime(raw: unknown): string {
  if (raw == null || raw === "") return "—"
  if (raw instanceof Date) {
    return formatSubscriptionTimestamp(raw)
  }
  return formatSubscriptionTimestamp(String(raw))
}

/** Future scheduled cancellation from Stripe cancel_at or cancel_at_period_end + current_period_end. */
export function getScheduledCancellationAt(
  profile: unknown,
  now = new Date()
): Date | null {
  if (!profile || typeof profile !== "object") return null

  const cancelAt = parseProfileDate(
    (profile as { cancel_at?: unknown }).cancel_at
  )
  if (cancelAt != null && cancelAt > now) {
    return cancelAt
  }

  if (isCancelAtPeriodEnd(profile)) {
    const periodEnd = parseProfileDate(
      (profile as { current_period_end?: unknown }).current_period_end
    )
    if (periodEnd != null && periodEnd > now) {
      return periodEnd
    }
  }

  return null
}

export function shouldShowScheduledCancellation(
  profile: unknown,
  now = new Date()
): boolean {
  return getScheduledCancellationAt(profile, now) != null
}

export function formatScheduledCancellation(profile: unknown): string {
  const at = getScheduledCancellationAt(profile)
  if (!at) return "—"
  return formatSubscriptionTimestamp(at)
}

export function shouldShowTrialInfo(profile: unknown): boolean {
  if (!profile) return false
  return normalizeSubscriptionStatus(profile) === "trialing" || isTrialEndInFuture(profile)
}

export function shouldShowRenewalInfo(profile: unknown): boolean {
  if (!profile) return false
  if (shouldShowScheduledCancellation(profile)) return false
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
