import { NextResponse } from "next/server"
import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadActiveAppleSubscriptionForUser } from "@/lib/appleSubscription"
import {
  isTraxProActive,
  TRAXPRO_ENTITLEMENT_PROFILE_COLUMNS,
  type TraxProEntitlementProfile,
} from "@/lib/traxProEntitlement"

export { TRAXPRO_ENTITLEMENT_PROFILE_COLUMNS as PRO_ENTITLEMENT_PROFILE_COLUMNS }

export type ProEntitlementProfile = TraxProEntitlementProfile

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
    .select(TRAXPRO_ENTITLEMENT_PROFILE_COLUMNS)
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

  const appleSubscription = await loadActiveAppleSubscriptionForUser(
    supabaseServiceRole,
    userId
  )

  if (!isTraxProActive(loaded.profile, appleSubscription)) {
    return {
      ok: false,
      response: NextResponse.json(
        {
          error: options?.error ?? "Pro required",
          reply:
            options?.reply ??
            "This feature requires TraxPro.",
        },
        { status: 403 }
      ),
    }
  }

  return { ok: true, profile: loaded.profile }
}
