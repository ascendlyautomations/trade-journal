import type { SupabaseClient } from "@supabase/supabase-js"
import { isProActive } from "@/lib/subscription"
import { clearSignupFlow } from "@/lib/signupFlow"
import { clearSettingsProfileCache } from "@/lib/settingsProfileCache"
import { clearUserBootstrapProfile } from "@/lib/userBootstrapCache"
import {
  fetchSettingsProfileRow,
  persistSettingsProfileEverywhere,
} from "@/lib/settingsProfileSync"

type MembershipProfile = {
  is_pro?: boolean | null
  subscription_status?: string | null
  trial_end?: string | null
}

type SyncMembershipOptions<T extends MembershipProfile> = {
  maxAttempts?: number
  intervalMs?: number
  pickProfile: (row: unknown) => T | null
}

export type StripeMembershipSyncResult<T extends MembershipProfile> = {
  profile: T | null
  reconciled: boolean
}

/** Poll Supabase until Stripe webhook membership is visible (or attempts exhausted). */
export async function syncMembershipAfterStripeCheckout<T extends MembershipProfile>(
  client: SupabaseClient,
  userId: string,
  options: SyncMembershipOptions<T>,
): Promise<StripeMembershipSyncResult<T>> {
  const maxAttempts = options.maxAttempts ?? 10
  const intervalMs = options.intervalMs ?? 800

  clearSignupFlow()
  clearSettingsProfileCache(userId)
  clearUserBootstrapProfile(userId)

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const row = await fetchSettingsProfileRow(client, userId, {
      force: true,
      skipCacheWrite: true,
    })
    const picked = options.pickProfile(row)

    if (picked && isProActive(picked)) {
      if (row) {
        persistSettingsProfileEverywhere(userId, row)
      }
      return { profile: picked, reconciled: true }
    }

    if (attempt < maxAttempts - 1) {
      await new Promise((resolve) => setTimeout(resolve, intervalMs))
    }
  }

  clearSettingsProfileCache(userId)
  clearUserBootstrapProfile(userId)
  return { profile: null, reconciled: false }
}
