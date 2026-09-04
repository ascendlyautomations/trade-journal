import { NextResponse } from "next/server"
import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isProActive } from "@/lib/subscription"

export const PRO_ENTITLEMENT_PROFILE_COLUMNS =
  "is_pro,creator_access,subscription_status,trial_end,early_access_enrolled_at,early_access_started_at,early_access_status,early_access_ends_at,early_access_campaign_id,early_access_enrollment_source"

export type ProEntitlementProfile = Parameters<typeof isProActive>[0]

export type ProEntitlementCheck =
  | { ok: true; profile: NonNullable<ProEntitlementProfile> }
  | { ok: false; response: NextResponse }

export async function loadProEntitlementProfile(
  userId: string
): Promise<
  | { ok: true; profile: NonNullable<ProEntitlementProfile> }
  | { ok: false; response: NextResponse }
> {
  const { data: profile, error } = await supabaseServiceRole
    .from("profiles")
    .select(PRO_ENTITLEMENT_PROFILE_COLUMNS)
    .eq("id", userId)
    .single<ProEntitlementProfile>()

  if (error || !profile) {
    return {
      ok: false,
      response: NextResponse.json(
        { error: "Could not verify subscription" },
        { status: 500 }
      ),
    }
  }

  return { ok: true, profile }
}

export async function requireProEntitlement(
  userId: string,
  options?: {
    error?: string
    reply?: string
  }
): Promise<ProEntitlementCheck> {
  const loaded = await loadProEntitlementProfile(userId)
  if (!loaded.ok) return loaded

  if (!isProActive(loaded.profile)) {
    return {
      ok: false,
      response: NextResponse.json(
        {
          error: options?.error ?? "Pro required",
          reply:
            options?.reply ??
            "This AI feature is available on TraxPro. Upgrade your plan on the web to unlock it.",
        },
        { status: 403 }
      ),
    }
  }

  return { ok: true, profile: loaded.profile }
}
