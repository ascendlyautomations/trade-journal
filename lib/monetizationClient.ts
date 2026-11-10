"use client"

import {
  getSupabaseApiAccessToken,
  isAuthenticatedMemberUser,
} from "./supabaseBearerFetch"
import {
  MONETIZATION_FLAGS_FAIL_CLOSED,
  type EffectiveMonetizationFlags,
} from "./monetizationConfig.ts"

const cacheByUser = new Map<string, EffectiveMonetizationFlags>()

export async function fetchMonetizationFlags(
  userId: string
): Promise<EffectiveMonetizationFlags> {
  if (!isAuthenticatedMemberUser({ id: userId })) {
    return { ...MONETIZATION_FLAGS_FAIL_CLOSED }
  }
  const token = await getSupabaseApiAccessToken()
  if (!token) return { ...MONETIZATION_FLAGS_FAIL_CLOSED }

  try {
    const res = await fetch("/api/billing/config", {
      headers: { Authorization: `Bearer ${token}` },
    })
    if (!res.ok) return { ...MONETIZATION_FLAGS_FAIL_CLOSED }
    const body = (await res.json()) as EffectiveMonetizationFlags
    const flags: EffectiveMonetizationFlags = {
      iosPaywallEnabled: body.iosPaywallEnabled === true,
      webPaywallEnabled: body.webPaywallEnabled === true,
      entitlementEnforcementEnabled: body.entitlementEnforcementEnabled === true,
    }
    cacheByUser.set(userId, flags)
    return flags
  } catch {
    return cacheByUser.get(userId) ?? { ...MONETIZATION_FLAGS_FAIL_CLOSED }
  }
}

export function readCachedMonetizationFlags(
  userId: string | null | undefined
): EffectiveMonetizationFlags | null {
  if (!userId) return null
  return cacheByUser.get(userId) ?? null
}

export function clearMonetizationFlagsCache(userId?: string): void {
  if (userId) cacheByUser.delete(userId)
  else cacheByUser.clear()
}
