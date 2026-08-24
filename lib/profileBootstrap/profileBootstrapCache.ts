/**
 * Viewer-scoped Profile bootstrap cache with soft-stale SWR semantics.
 * Canonical key: viewerKey|profileId. Identifier aliases map to profileId.
 */

import type { ProfileBootstrapV1 } from "./contracts.ts"
import type { ProfileBootstrapLoadResult } from "./profileBootstrapRepository.ts"
import { clearProfileBootstrapFlights } from "./profileBootstrapSingleFlight.ts"

export const PROFILE_BOOTSTRAP_FRESH_MS = 60_000
export const PROFILE_BOOTSTRAP_SOFT_STALE_MS = 10 * 60_000
export const PROFILE_BOOTSTRAP_HARD_EXPIRE_MS = 30 * 60_000

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export type ProfileBootstrapCacheFreshness =
  | "fresh"
  | "soft_stale"
  | "hard_expired"
  | "miss"

export type ProfileBootstrapCacheEntry = {
  viewerKey: string
  profileId: string
  /** Primary username at write time (for invalidation on rename). */
  username: string | null
  accessKey: string
  bootstrap: ProfileBootstrapV1
  loadResult: ProfileBootstrapLoadResult
  fetchedAt: number
}

type CacheStore = {
  byCanonicalKey: Map<string, ProfileBootstrapCacheEntry>
  aliasToProfileId: Map<string, string>
}

const GLOBAL_KEY = Symbol.for("tradetraxs.profileBootstrap.cache")

function store(): CacheStore {
  const g = globalThis as typeof globalThis & { [GLOBAL_KEY]?: CacheStore }
  if (!g[GLOBAL_KEY]) {
    g[GLOBAL_KEY] = { byCanonicalKey: new Map(), aliasToProfileId: new Map() }
  }
  return g[GLOBAL_KEY]
}

export function profileBootstrapViewerKey(
  viewerId: string | null | undefined
): string {
  return viewerId ? String(viewerId) : "anon"
}

export function profileBootstrapAccessKey(
  bootstrap: ProfileBootstrapV1
): string {
  const v = bootstrap.data.viewer
  return [
    v.is_own_profile ? "1" : "0",
    v.can_view_trades ? "1" : "0",
    v.is_following ? "1" : "0",
    v.is_requested ? "1" : "0",
  ].join("|")
}

export function normalizeProfileBootstrapIdentifier(
  identifier: string
): string {
  return identifier.trim().toLowerCase()
}

export function profileBootstrapCanonicalCacheKey(
  viewerKey: string,
  profileId: string
): string {
  return `${viewerKey}|${String(profileId).toLowerCase()}`
}

function aliasKey(viewerKey: string, identifier: string): string {
  return `${viewerKey}|${normalizeProfileBootstrapIdentifier(identifier)}`
}

export function resolveProfileBootstrapCacheProfileId(
  viewerKey: string,
  identifier: string
): string | null {
  const normalized = normalizeProfileBootstrapIdentifier(identifier)
  if (UUID_RE.test(normalized)) return normalized
  return store().aliasToProfileId.get(aliasKey(viewerKey, normalized)) ?? null
}

function registerAliases(
  viewerKey: string,
  profileId: string,
  identifiers: string[]
) {
  const s = store()
  for (const raw of identifiers) {
    const id = normalizeProfileBootstrapIdentifier(raw)
    if (!id) continue
    s.aliasToProfileId.set(aliasKey(viewerKey, id), String(profileId).toLowerCase())
  }
}

function clearAliasesForProfile(viewerKey: string, profileId: string) {
  const s = store()
  const pid = String(profileId).toLowerCase()
  for (const [alias, target] of s.aliasToProfileId) {
    if (target === pid && alias.startsWith(`${viewerKey}|`)) {
      s.aliasToProfileId.delete(alias)
    }
  }
}

export function profileBootstrapCacheAgeMs(fetchedAt: number): number {
  return Date.now() - fetchedAt
}

export function profileBootstrapCacheFreshness(
  fetchedAt: number
): ProfileBootstrapCacheFreshness {
  const age = profileBootstrapCacheAgeMs(fetchedAt)
  if (age <= PROFILE_BOOTSTRAP_FRESH_MS) return "fresh"
  if (age <= PROFILE_BOOTSTRAP_HARD_EXPIRE_MS) return "soft_stale"
  return "hard_expired"
}

export function shouldRevalidateProfileBootstrapCache(
  fetchedAt: number
): boolean {
  return profileBootstrapCacheAgeMs(fetchedAt) > PROFILE_BOOTSTRAP_FRESH_MS
}

export function readProfileBootstrapCache(
  viewerKey: string,
  identifier: string
): {
  entry: ProfileBootstrapCacheEntry | null
  freshness: ProfileBootstrapCacheFreshness
  resolvedProfileId: string | null
} {
  const resolvedProfileId =
    UUID_RE.test(normalizeProfileBootstrapIdentifier(identifier))
      ? normalizeProfileBootstrapIdentifier(identifier)
      : resolveProfileBootstrapCacheProfileId(viewerKey, identifier)

  if (!resolvedProfileId) {
    return { entry: null, freshness: "miss", resolvedProfileId: null }
  }

  const key = profileBootstrapCanonicalCacheKey(viewerKey, resolvedProfileId)
  const entry = store().byCanonicalKey.get(key) ?? null
  if (!entry || entry.viewerKey !== viewerKey) {
    return { entry: null, freshness: "miss", resolvedProfileId }
  }
  const freshness = profileBootstrapCacheFreshness(entry.fetchedAt)
  if (freshness === "hard_expired") {
    invalidateProfileBootstrapCacheEntry(viewerKey, resolvedProfileId)
    return { entry: null, freshness: "hard_expired", resolvedProfileId }
  }
  return { entry, freshness, resolvedProfileId }
}

export function writeProfileBootstrapCache(
  viewerKey: string,
  identifier: string,
  profileId: string,
  bootstrap: ProfileBootstrapV1,
  loadResult: ProfileBootstrapLoadResult
): void {
  const pid = String(profileId).toLowerCase()
  const username =
    typeof bootstrap.data.profile?.username === "string"
      ? bootstrap.data.profile.username
      : null
  const canonicalKey = profileBootstrapCanonicalCacheKey(viewerKey, pid)
  const existing = store().byCanonicalKey.get(canonicalKey)
  if (
    existing?.username &&
    username &&
    existing.username.toLowerCase() !== username.toLowerCase()
  ) {
    clearAliasesForProfile(viewerKey, pid)
  }

  store().byCanonicalKey.set(canonicalKey, {
    viewerKey,
    profileId: pid,
    username,
    accessKey: profileBootstrapAccessKey(bootstrap),
    bootstrap,
    loadResult,
    fetchedAt: Date.now(),
  })

  const aliases = [identifier, pid]
  if (username) aliases.push(username)
  registerAliases(viewerKey, pid, aliases)
}

export function patchProfileBootstrapCacheLoadResult(
  viewerKey: string,
  identifier: string,
  loadResult: ProfileBootstrapLoadResult
): void {
  const cached = readProfileBootstrapCache(viewerKey, identifier)
  if (!cached.entry || !cached.resolvedProfileId) return
  const key = profileBootstrapCanonicalCacheKey(
    viewerKey,
    cached.resolvedProfileId
  )
  store().byCanonicalKey.set(key, {
    ...cached.entry,
    loadResult,
    fetchedAt: Date.now(),
  })
}

function invalidateProfileBootstrapCacheEntry(
  viewerKey: string,
  profileId: string
): void {
  const pid = String(profileId).toLowerCase()
  store().byCanonicalKey.delete(profileBootstrapCanonicalCacheKey(viewerKey, pid))
  clearAliasesForProfile(viewerKey, pid)
}

export function invalidateProfileBootstrapCache(options?: {
  viewerKey?: string | null
  profileId?: string | null
  identifier?: string | null
}): void {
  const s = store()
  if (!options?.viewerKey && !options?.profileId && !options?.identifier) {
    s.byCanonicalKey.clear()
    s.aliasToProfileId.clear()
    clearProfileBootstrapFlights()
    return
  }

  if (options.viewerKey && options.profileId) {
    invalidateProfileBootstrapCacheEntry(options.viewerKey, options.profileId)
  } else if (options.viewerKey && options.identifier) {
    const pid = resolveProfileBootstrapCacheProfileId(
      options.viewerKey,
      options.identifier
    )
    if (pid) invalidateProfileBootstrapCacheEntry(options.viewerKey, pid)
  } else if (options.profileId) {
    for (const [k, entry] of s.byCanonicalKey) {
      if (entry.profileId === String(options.profileId).toLowerCase()) {
        s.byCanonicalKey.delete(k)
      }
    }
    for (const [alias, target] of s.aliasToProfileId) {
      if (target === String(options.profileId).toLowerCase()) {
        s.aliasToProfileId.delete(alias)
      }
    }
  }

  if (options.viewerKey) clearProfileBootstrapFlights(options.viewerKey)
}

/** @internal */
export function __resetProfileBootstrapCacheForTests(): void {
  const s = store()
  s.byCanonicalKey.clear()
  s.aliasToProfileId.clear()
  clearProfileBootstrapFlights()
}

/** @deprecated Use profileBootstrapCanonicalCacheKey */
export function profileBootstrapCacheKey(
  viewerKey: string,
  identifier: string
): string {
  const pid = resolveProfileBootstrapCacheProfileId(viewerKey, identifier)
  if (pid) return profileBootstrapCanonicalCacheKey(viewerKey, pid)
  return aliasKey(viewerKey, identifier)
}
