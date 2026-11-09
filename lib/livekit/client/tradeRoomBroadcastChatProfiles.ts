import type { SupabaseClient } from "@supabase/supabase-js"
import { normalizeAvatarSrc } from "../../profileAvatarUrl.ts"

export type BroadcastChatProfile = {
  userId: string
  displayName: string
  avatarUrl: string | null
}

/** Same URL rules as SafeProfileAvatar / feed (Supabase paths + public URLs). */
export function normalizeBroadcastChatAvatarUrl(
  src: string | null | undefined
): string | null {
  return normalizeAvatarSrc(src)
}

const cache = new Map<string, BroadcastChatProfile>()

export function peekBroadcastChatProfile(
  userId: string
): BroadcastChatProfile | undefined {
  return cache.get(userId)
}

export function seedBroadcastChatProfile(profile: BroadcastChatProfile): void {
  cache.set(profile.userId, profile)
}

export function clearBroadcastChatProfileCache(): void {
  cache.clear()
}

export async function resolveBroadcastChatProfiles(
  supabase: SupabaseClient,
  userIds: string[]
): Promise<Map<string, BroadcastChatProfile>> {
  const unique = [...new Set(userIds.filter(Boolean))]
  const result = new Map<string, BroadcastChatProfile>()
  const missing: string[] = []

  for (const id of unique) {
    const hit = cache.get(id)
    if (hit) {
      result.set(id, hit)
    } else {
      missing.push(id)
    }
  }

  if (missing.length === 0) return result

  const { data, error } = await supabase
    .from("profiles")
    .select("id, username, name, avatar_url")
    .in("id", missing)

  if (error) {
    console.warn("[broadcast/chat] profile lookup failed", error.message)
    return result
  }

  for (const row of data ?? []) {
    const displayName =
      row.name?.trim() || row.username?.trim() || "Member"
    const profile: BroadcastChatProfile = {
      userId: row.id,
      displayName,
      avatarUrl: normalizeBroadcastChatAvatarUrl(row.avatar_url),
    }
    cache.set(row.id, profile)
    result.set(row.id, profile)
  }

  for (const id of missing) {
    if (!result.has(id)) {
      const fallback: BroadcastChatProfile = {
        userId: id,
        displayName: "Member",
        avatarUrl: null,
      }
      cache.set(id, fallback)
      result.set(id, fallback)
    }
  }

  return result
}
