import { NextResponse } from "next/server"
import type { SupabaseClient } from "@supabase/supabase-js"
import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import type { Database } from "@/lib/database.types.ts"
import { readProEntitlementProfile } from "@/lib/proEntitlementProfileRead.ts"
import {
  loadTraxProEntitlementSnapshot,
  minimalEntitlementProfile,
  TRAXPRO_ENTITLEMENT_PROFILE_COLUMNS,
  type TraxProEntitlementProfile,
} from "@/lib/traxProEntitlement"

export { TRAXPRO_ENTITLEMENT_PROFILE_COLUMNS as PRO_ENTITLEMENT_PROFILE_COLUMNS }

export type ProEntitlementProfile = TraxProEntitlementProfile

export type ProEntitlementCheck =
  | { ok: true; profile: NonNullable<ProEntitlementProfile> }
  | { ok: false; response: NextResponse }

function entitlementUnavailable(reason?: string) {
  return {
    ok: false as const,
    response: NextResponse.json(
      {
        error: "Could not verify subscription",
        reply:
          "We couldn't verify your TraxsPro subscription right now. Please try again in a moment.",
        code: "entitlement_check_failed",
        ...(reason ? { detail: reason } : {}),
      },
      { status: 503 }
    ),
  }
}

export async function loadProEntitlementProfile(
  userId: string,
  options?: {
    client?: SupabaseClient<Database>
    timeoutMs?: number
  }
): Promise<
  | { ok: true; profile: NonNullable<ProEntitlementProfile> }
  | { ok: false; response: NextResponse }
> {
  const profile = await readProEntitlementProfile(
    options?.client ?? supabaseServiceRole,
    userId,
    { timeoutMs: options?.timeoutMs }
  )
  if (!profile) return entitlementUnavailable()
  return { ok: true, profile }
}

export async function requireProEntitlement(
  userId: string,
  options?: {
    error?: string
    reply?: string
  }
): Promise<ProEntitlementCheck> {
  const loaded = await loadTraxProEntitlementSnapshot(
    supabaseServiceRole,
    userId
  )
  if (!loaded.ok) {
    return entitlementUnavailable(loaded.reason)
  }

  if (!loaded.snapshot.traxProActive) {
    return {
      ok: false,
      response: NextResponse.json(
        {
          error: options?.error ?? "Pro required",
          reply:
            options?.reply ??
            "This feature requires TraxPro.",
          code: "pro_required",
        },
        { status: 403 }
      ),
    }
  }

  const profile =
    loaded.snapshot.profile ?? minimalEntitlementProfile()
  return { ok: true, profile }
}
