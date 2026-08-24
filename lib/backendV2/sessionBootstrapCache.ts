/**
 * Canonical Session Bootstrap cache — single owner for session-scoped data
 * after rpc_v1_session_bootstrap (flag ON).
 *
 * Realtime / Navbar / admin checks MUST read+patch here instead of re-bootstrapping.
 *
 * Stored on globalThis so duplicate Next.js module instances share one cache.
 */

import type {
  BadgeCountsV1,
  SessionBootstrapV1,
  SessionProfileV1,
} from "./contracts.ts"
import { clearSessionBootstrapFlights } from "./sessionBootstrapSingleFlight.ts"
import { clearSessionBootstrapRpcGate } from "./sessionBootstrapRpcGate.ts"

type Entry = {
  userId: string
  bootstrap: SessionBootstrapV1
  fetchedAt: number
  source: "rpc" | "rest" | "cache"
}

type CacheStore = {
  entry: Entry | null
  listeners: Set<() => void>
}

const GLOBAL_KEY = "__tradetraxs_session_bootstrap_cache__" as const

function store(): CacheStore {
  const g = globalThis as typeof globalThis & {
    [GLOBAL_KEY]?: CacheStore
  }
  if (!g[GLOBAL_KEY]) {
    g[GLOBAL_KEY] = { entry: null, listeners: new Set() }
  }
  return g[GLOBAL_KEY]
}

function notify() {
  for (const listener of store().listeners) listener()
}

export function subscribeSessionBootstrapCache(listener: () => void): () => void {
  store().listeners.add(listener)
  return () => store().listeners.delete(listener)
}

export function readSessionBootstrapCache(
  userId: string | null | undefined
): SessionBootstrapV1 | null {
  const entry = store().entry
  if (!userId || !entry) return null
  if (entry.userId !== userId) return null
  return entry.bootstrap
}

export function writeSessionBootstrapCache(
  userId: string,
  bootstrap: SessionBootstrapV1,
  source: "rpc" | "rest" | "cache" = "rpc"
): void {
  store().entry = { userId, bootstrap, fetchedAt: Date.now(), source }
  notify()
}

export function clearSessionBootstrapCache(): void {
  store().entry = null
  clearSessionBootstrapFlights()
  clearSessionBootstrapRpcGate()
  notify()
}

/**
 * Explicit invalidate — logout, account switch, or forced re-bootstrap.
 * Same as clearSessionBootstrapCache (clears cache + single-flight + RPC gate).
 */
export function invalidateSessionBootstrap(userId?: string | null): void {
  if (userId) {
    const entry = store().entry
    if (entry && entry.userId === userId) {
      store().entry = null
    }
    clearSessionBootstrapFlights(userId)
    clearSessionBootstrapRpcGate()
    notify()
    return
  }
  clearSessionBootstrapCache()
}

export function sessionBootstrapCacheMeta(
  userId: string | null | undefined
): { hit: boolean; ageMs: number | null; source: Entry["source"] | null } {
  const entry = store().entry
  if (!userId || !entry || entry.userId !== userId) {
    return { hit: false, ageMs: null, source: null }
  }
  return {
    hit: true,
    ageMs: Date.now() - entry.fetchedAt,
    source: entry.source,
  }
}

export function getSessionBadges(
  userId: string | null | undefined
): BadgeCountsV1 | null {
  return readSessionBootstrapCache(userId)?.data.badges ?? null
}

export function patchSessionBadges(
  userId: string,
  patch: Partial<BadgeCountsV1>
): void {
  const current = readSessionBootstrapCache(userId)
  if (!current) return
  writeSessionBootstrapCache(
    userId,
    {
      ...current,
      data: {
        ...current.data,
        badges: {
          ...current.data.badges,
          ...patch,
        },
      },
    },
    "cache"
  )
}

export function getSessionFollowingIds(
  userId: string | null | undefined
): string[] | null {
  const boot = readSessionBootstrapCache(userId)
  if (!boot) return null
  return boot.data.following_ids
}

export function patchSessionFollowingIds(
  userId: string,
  followingIds: string[]
): void {
  const current = readSessionBootstrapCache(userId)
  if (!current) return
  writeSessionBootstrapCache(
    userId,
    {
      ...current,
      data: {
        ...current.data,
        following_ids: followingIds,
      },
    },
    "cache"
  )
}

export function getSessionIsAdmin(
  userId: string | null | undefined
): boolean | null {
  const boot = readSessionBootstrapCache(userId)
  if (!boot) return null
  return Boolean(boot.data.viewer.entitlement.flags?.is_admin)
}

export function getSessionProfileSlice(
  userId: string | null | undefined
): SessionProfileV1 | null {
  return readSessionBootstrapCache(userId)?.data.session_profile ?? null
}

export function patchSessionProfileSlice(
  userId: string,
  profile: Partial<SessionProfileV1> & Record<string, unknown>
): void {
  const current = readSessionBootstrapCache(userId)
  if (!current) return
  const nextProfile = {
    ...current.data.session_profile,
    ...profile,
  } as SessionProfileV1
  writeSessionBootstrapCache(
    userId,
    {
      ...current,
      data: {
        ...current.data,
        session_profile: nextProfile,
        viewer: {
          ...current.data.viewer,
          username:
            typeof profile.username === "string"
              ? profile.username
              : current.data.viewer.username,
          avatar_url:
            profile.avatar_url !== undefined
              ? (profile.avatar_url as string | null)
              : current.data.viewer.avatar_url,
          is_private:
            typeof profile.is_private === "boolean"
              ? profile.is_private
              : current.data.viewer.is_private,
        },
      },
    },
    "cache"
  )
}
