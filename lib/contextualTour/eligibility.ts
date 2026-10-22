import { CONTEXTUAL_TOUR_ACCOUNT_CREATED_AT_CUTOFF_ISO } from "./catalog"

export function parseAccountCreatedAt(
  createdAt: string | null | undefined
): Date | null {
  if (!createdAt) return null
  const date = new Date(createdAt)
  return Number.isNaN(date.getTime()) ? null : date
}

const cutoffDate = new Date(CONTEXTUAL_TOUR_ACCOUNT_CREATED_AT_CUTOFF_ISO)

export function isAccountEligibleForAutoTour(createdAt: Date | null): boolean {
  if (!createdAt) return false
  return createdAt >= cutoffDate
}

export function shouldAutomaticallyPresentTour(
  createdAt: Date | null,
  dismissedVersion: number,
  tourVersion: number
): boolean {
  if (!isAccountEligibleForAutoTour(createdAt)) return false
  return dismissedVersion < tourVersion
}
