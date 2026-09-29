import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "./database.types.ts"
import {
  isAppleSubscriptionActive,
  loadActiveAppleSubscriptionForUser,
  type AppleSubscriptionRow,
} from "./appleSubscription.ts"
import { launchAccessGrantApplies } from "./monetizationConfig.ts"
import { loadLaunchAccessPolicy } from "./server/monetizationConfig.ts"
import { isProActive } from "./subscription.ts"

export const TRAXPRO_ENTITLEMENT_PROFILE_COLUMNS =
  "is_pro,creator_access,subscription_status,trial_end,early_access_enrolled_at,early_access_started_at,early_access_status,early_access_ends_at,early_access_campaign_id,early_access_enrollment_source,billing_interval,current_period_end,cancel_at_period_end"

export type TraxProEntitlementProfile = Parameters<typeof isProActive>[0] & {
  billing_interval?: string | null
  current_period_end?: string | null
  cancel_at_period_end?: boolean | null
}

export type TraxProEntitlementSource =
  | "none"
  | "stripe"
  | "apple"
  | "manual"
  | "creator"
  | "early_access"
  | "launch_access"

export type TraxProEntitlementSnapshot = {
  traxProActive: boolean
  source: TraxProEntitlementSource
  profile: TraxProEntitlementProfile | null
  appleSubscription: AppleSubscriptionRow | null
  billingInterval: string | null
  subscriptionStatus: string | null
  trialEndsAt: string | null
  currentPeriodEndsAt: string | null
  cancelAtPeriodEnd: boolean
  appleExpiresAt: string | null
  /** When access ends. Null means the grant has no scheduled expiry (manual, creator, lifetime). */
  accessExpiresAt: string | null
  issuedAt: string
  appleSubscriptionStatus: string | null
  appleRevokedAt: string | null
}

function resolveStripeLikeSource(
  profile: TraxProEntitlementProfile
): TraxProEntitlementSource | null {
  const status = String(profile.subscription_status ?? "").toLowerCase().trim()
  if (status === "active" || status === "trialing") return "stripe"
  const trialEndRaw = profile.trial_end
  if (trialEndRaw) {
    const trialEnd = new Date(trialEndRaw)
    if (!Number.isNaN(trialEnd.getTime()) && trialEnd > new Date()) {
      return "stripe"
    }
  }
  return null
}

function resolveEarlyAccessSource(
  profile: TraxProEntitlementProfile
): boolean {
  if (
    profile.early_access_status === "active" &&
    profile.early_access_enrolled_at != null &&
    profile.early_access_started_at != null &&
    profile.early_access_campaign_id === "traxs_pro_for_life_v1" &&
    (profile.early_access_enrollment_source === "standard_email" ||
      profile.early_access_enrollment_source === "standard_oauth")
  ) {
    const endRaw = profile.early_access_ends_at
    if (endRaw) {
      const end = new Date(endRaw)
      return !Number.isNaN(end.getTime()) && end > new Date()
    }
  }
  return false
}

export function resolveTraxProEntitlementSource(
  profile: TraxProEntitlementProfile | null | undefined,
  appleSubscription: AppleSubscriptionRow | null | undefined
): TraxProEntitlementSource {
  if (!profile && !appleSubscription) return "none"

  if (profile?.creator_access === true) return "creator"
  if (profile?.is_pro === true) return "manual"

  if (resolveEarlyAccessSource(profile ?? {})) return "early_access"

  const stripeLike = profile ? resolveStripeLikeSource(profile) : null
  if (stripeLike) return stripeLike

  if (isAppleSubscriptionActive(appleSubscription)) return "apple"

  return "none"
}

export function isTraxProActive(
  profile: TraxProEntitlementProfile | null | undefined,
  appleSubscription?: AppleSubscriptionRow | null
): boolean {
  if (isProActive(profile)) return true
  return isAppleSubscriptionActive(appleSubscription)
}

export function resolveEntitlementAccessExpiresAt(input: {
  source: TraxProEntitlementSource
  traxProActive: boolean
  trialEndsAt: string | null
  currentPeriodEndsAt: string | null
  appleExpiresAt: string | null
  earlyAccessEndsAt?: string | null
}): string | null {
  if (!input.traxProActive) return null
  switch (input.source) {
    case "apple":
      return input.appleExpiresAt
    case "stripe":
      return input.trialEndsAt ?? input.currentPeriodEndsAt
    case "early_access":
      return input.earlyAccessEndsAt ?? null
    case "manual":
    case "creator":
    case "launch_access":
    case "none":
      return null
    default:
      return null
  }
}

export function buildTraxProEntitlementSnapshot(
  profile: TraxProEntitlementProfile | null,
  appleSubscription: AppleSubscriptionRow | null,
  options?: {
    launchAccess?: {
      launchAccessMode?: "none" | "created_before_cutoff" | null
      launchAccessCutoffAt?: string | null
    } | null
    profileCreatedAt?: string | null
    issuedAt?: Date
  }
): TraxProEntitlementSnapshot {
  let traxProActive = isTraxProActive(profile, appleSubscription)
  let source: TraxProEntitlementSource = traxProActive
    ? resolveTraxProEntitlementSource(profile, appleSubscription)
    : "none"

  if (
    !traxProActive &&
    launchAccessGrantApplies(options?.profileCreatedAt, options?.launchAccess)
  ) {
    traxProActive = true
    source = "launch_access"
  }

  const billingInterval =
    (traxProActive && source === "apple"
      ? appleSubscription?.billing_interval
      : profile?.billing_interval) ?? null

  const trialEndsAt = profile?.trial_end ?? null
  const currentPeriodEndsAt = profile?.current_period_end ?? null
  const appleExpiresAt = appleSubscription?.expires_at ?? null

  return {
    traxProActive,
    source,
    profile,
    appleSubscription,
    billingInterval,
    subscriptionStatus: profile?.subscription_status ?? null,
    trialEndsAt,
    currentPeriodEndsAt,
    cancelAtPeriodEnd: profile?.cancel_at_period_end === true,
    appleExpiresAt,
    accessExpiresAt: resolveEntitlementAccessExpiresAt({
      source,
      traxProActive,
      trialEndsAt,
      currentPeriodEndsAt,
      appleExpiresAt,
      earlyAccessEndsAt: profile?.early_access_ends_at ?? null,
    }),
    issuedAt: (options?.issuedAt ?? new Date()).toISOString(),
    appleSubscriptionStatus: appleSubscription?.status ?? null,
    appleRevokedAt: appleSubscription?.revoked_at ?? null,
  }
}

export async function loadTraxProEntitlementSnapshot(
  supabase: SupabaseClient<Database>,
  userId: string
): Promise<
  | { ok: true; snapshot: TraxProEntitlementSnapshot }
  | { ok: false; reason: string }
> {
  const { data: profileRow, error } = await supabase
    .from("profiles")
    .select(`${TRAXPRO_ENTITLEMENT_PROFILE_COLUMNS},created_at`)
    .eq("id", userId)
    .single()

  if (error || !profileRow) {
    return { ok: false, reason: "Could not load profile" }
  }

  const createdAt =
    profileRow.created_at != null ? String(profileRow.created_at) : null
  const profile = profileRow as TraxProEntitlementProfile
  const appleSubscription = await loadActiveAppleSubscriptionForUser(
    supabase,
    userId
  )
  const launchAccess = await loadLaunchAccessPolicy(supabase)

  return {
    ok: true,
    snapshot: buildTraxProEntitlementSnapshot(profile, appleSubscription, {
      launchAccess,
      profileCreatedAt: createdAt,
    }),
  }
}
