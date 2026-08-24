/**
 * Dual-run comparison for Session Bootstrap (development).
 * Logs mismatches — never silently ignores them.
 */

import type { SessionBootstrapV1 } from "./contracts.ts"

export type SessionBootstrapMismatch = {
  path: string
  rest: unknown
  rpc: unknown
}

function sortedIds(ids: string[]): string[] {
  return [...ids].map(String).sort()
}

function normalizeAccounts(
  rows: SessionBootstrapV1["data"]["accounts_summary"]
): Array<{ id: string; name: string | null; type: string | null; is_active: boolean }> {
  return [...rows]
    .map((a) => ({
      id: String(a.id),
      name: a.name ?? null,
      type: a.type ?? null,
      is_active: Boolean(a.is_active),
    }))
    .sort((a, b) => a.id.localeCompare(b.id))
}

export function compareSessionBootstraps(
  rest: SessionBootstrapV1,
  rpc: SessionBootstrapV1
): SessionBootstrapMismatch[] {
  const mismatches: SessionBootstrapMismatch[] = []

  const restProfile = rest.data.session_profile
  const rpcProfile = rpc.data.session_profile
  const profileKeys: Array<keyof typeof restProfile> = [
    "id",
    "username",
    "avatar_url",
    "is_pro",
    "creator_access",
    "subscription_status",
    "onboarding_completed",
    "is_private",
    "is_banned",
    "use_free_tier",
    "is_beta_tester",
    "referral_code",
  ]
  for (const key of profileKeys) {
    const a = restProfile[key] ?? null
    const b = rpcProfile[key] ?? null
    if (String(a) !== String(b)) {
      mismatches.push({ path: `session_profile.${key}`, rest: a, rpc: b })
    }
  }

  if (rest.data.viewer.entitlement.plan !== rpc.data.viewer.entitlement.plan) {
    mismatches.push({
      path: "viewer.entitlement.plan",
      rest: rest.data.viewer.entitlement.plan,
      rpc: rpc.data.viewer.entitlement.plan,
    })
  }

  const restFollowing = sortedIds(rest.data.following_ids)
  const rpcFollowing = sortedIds(rpc.data.following_ids)
  if (JSON.stringify(restFollowing) !== JSON.stringify(rpcFollowing)) {
    mismatches.push({
      path: "following_ids",
      rest: restFollowing,
      rpc: rpcFollowing,
    })
  }

  const restAccounts = normalizeAccounts(rest.data.accounts_summary)
  const rpcAccounts = normalizeAccounts(rpc.data.accounts_summary)
  if (JSON.stringify(restAccounts) !== JSON.stringify(rpcAccounts)) {
    mismatches.push({
      path: "accounts_summary",
      rest: restAccounts,
      rpc: rpcAccounts,
    })
  }

  if (
    rest.data.badges.notifications_unread !==
    rpc.data.badges.notifications_unread
  ) {
    mismatches.push({
      path: "badges.notifications_unread",
      rest: rest.data.badges.notifications_unread,
      rpc: rpc.data.badges.notifications_unread,
    })
  }
  if (rest.data.badges.dm_unread !== rpc.data.badges.dm_unread) {
    mismatches.push({
      path: "badges.dm_unread",
      rest: rest.data.badges.dm_unread,
      rpc: rpc.data.badges.dm_unread,
    })
  }

  if (
    rest.data.prefs_min.notifications_enabled_summary !==
    rpc.data.prefs_min.notifications_enabled_summary
  ) {
    mismatches.push({
      path: "prefs_min.notifications_enabled_summary",
      rest: rest.data.prefs_min.notifications_enabled_summary,
      rpc: rpc.data.prefs_min.notifications_enabled_summary,
    })
  }

  return mismatches
}

export function logSessionBootstrapMismatches(
  mismatches: SessionBootstrapMismatch[]
): void {
  if (!mismatches.length) {
    // eslint-disable-next-line no-console
    console.debug("[backendV2.session] dual-run OK — REST and RPC match")
    return
  }
  // eslint-disable-next-line no-console
  console.warn(
    `[backendV2.session] dual-run MISMATCH (${mismatches.length})`,
    mismatches
  )
}
