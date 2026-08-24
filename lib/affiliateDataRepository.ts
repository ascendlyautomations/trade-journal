import type { SupabaseClient } from "@supabase/supabase-js"
import {
  AFFILIATE_CONNECT_SELECT,
  parseAffiliateConnectRow,
  type AffiliateConnectRow,
} from "./affiliateStripeConnect.ts"
import type { AffiliateApplicationRow } from "./affiliateApplication.ts"

const AFFILIATE_APPLICATION_SELECT_COLUMNS =
  [
    "id",
    "user_id",
    "social_handle",
    "followers",
    "requested_code",
    "status",
    "has_edited",
    "created_at",
    "reviewed_at",
    "reviewed_by",
  ].join(", ")

const CACHE_MS = 60_000
const SOFT_STALE_MS = 5 * 60_000

type ViewerAffiliateCache = {
  application: AffiliateApplicationRow | null | undefined
  connect: AffiliateConnectRow | null | undefined
  fetchedAt: number
  applicationInflight?: Promise<AffiliateApplicationRow | null>
  connectInflight?: Promise<AffiliateConnectRow | null>
}

const byViewer = new Map<string, ViewerAffiliateCache>()

function entryFor(userId: string): ViewerAffiliateCache {
  const key = userId.trim()
  let entry = byViewer.get(key)
  if (!entry) {
    entry = {
      application: undefined,
      connect: undefined,
      fetchedAt: 0,
    }
    byViewer.set(key, entry)
  }
  return entry
}

function isFresh(entry: ViewerAffiliateCache, force?: boolean): boolean {
  if (force) return false
  if (entry.fetchedAt <= 0) return false
  return Date.now() - entry.fetchedAt <= CACHE_MS
}

function parseApplicationRow(data: unknown): AffiliateApplicationRow | null {
  if (data == null || typeof data !== "object") return null
  const raw = data as Record<string, unknown>
  const id = raw.id != null ? String(raw.id).trim() : ""
  const user_id = raw.user_id != null ? String(raw.user_id).trim() : ""
  if (!id || !user_id) return null
  return {
    id,
    user_id,
    social_handle:
      raw.social_handle != null && String(raw.social_handle).trim() !== ""
        ? String(raw.social_handle)
        : null,
    followers:
      typeof raw.followers === "number" && Number.isFinite(raw.followers)
        ? Math.trunc(raw.followers)
        : null,
    requested_code:
      raw.requested_code != null && String(raw.requested_code).trim() !== ""
        ? String(raw.requested_code)
        : null,
    status: String(raw.status ?? "pending"),
    has_edited: Boolean(raw.has_edited),
    created_at: raw.created_at != null ? String(raw.created_at) : null,
    reviewed_at: raw.reviewed_at != null ? String(raw.reviewed_at) : null,
    reviewed_by: raw.reviewed_by != null ? String(raw.reviewed_by) : null,
  }
}

async function loadApplicationFromDb(
  client: SupabaseClient,
  userId: string
): Promise<AffiliateApplicationRow | null> {
  const { data, error } = await client
    .from("affiliate_applications")
    .select(AFFILIATE_APPLICATION_SELECT_COLUMNS)
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle()

  if (error) {
    console.error("[affiliateDataRepository] application load", error)
    return null
  }
  return parseApplicationRow(data)
}

async function loadConnectFromDb(
  client: SupabaseClient,
  userId: string
): Promise<AffiliateConnectRow | null> {
  const { data, error } = await client
    .from("affiliates")
    .select(AFFILIATE_CONNECT_SELECT)
    .eq("user_id", userId)
    .maybeSingle()

  if (error) {
    console.error("[affiliateDataRepository] affiliate connect load", error)
    return null
  }
  if (!data || typeof data !== "object") return null
  return parseAffiliateConnectRow(data as Record<string, unknown>)
}

export function getCachedAffiliateApplication(
  userId: string | null | undefined
): AffiliateApplicationRow | null | undefined {
  if (!userId?.trim()) return undefined
  const entry = byViewer.get(userId.trim())
  return entry?.application
}

export function getCachedAffiliateConnect(
  userId: string | null | undefined
): AffiliateConnectRow | null | undefined {
  if (!userId?.trim()) return undefined
  const entry = byViewer.get(userId.trim())
  return entry?.connect
}

export async function ensureAffiliateApplicationLoaded(
  client: SupabaseClient,
  userId: string,
  options?: { force?: boolean }
): Promise<AffiliateApplicationRow | null> {
  const key = userId.trim()
  if (!key) return null

  const entry = entryFor(key)
  if (entry.application !== undefined && isFresh(entry, options?.force)) {
    return entry.application
  }
  if (entry.applicationInflight) {
    return entry.applicationInflight
  }

  const inflight = loadApplicationFromDb(client, key).then((application) => {
    entry.application = application
    entry.fetchedAt = Date.now()
    delete entry.applicationInflight
    return application
  })
  entry.applicationInflight = inflight
  return inflight
}

export async function ensureAffiliateConnectLoaded(
  client: SupabaseClient,
  userId: string,
  options?: { force?: boolean }
): Promise<AffiliateConnectRow | null> {
  const key = userId.trim()
  if (!key) return null

  const entry = entryFor(key)
  if (entry.connect !== undefined && isFresh(entry, options?.force)) {
    return entry.connect
  }
  if (entry.connectInflight) {
    return entry.connectInflight
  }

  const inflight = loadConnectFromDb(client, key).then((connect) => {
    entry.connect = connect
    entry.fetchedAt = Date.now()
    delete entry.connectInflight
    return connect
  })
  entry.connectInflight = inflight
  return inflight
}

export function patchAffiliateApplicationCache(
  userId: string,
  application: AffiliateApplicationRow | null
) {
  const key = userId.trim()
  if (!key) return
  const entry = entryFor(key)
  entry.application = application
  entry.fetchedAt = Date.now()
}

export function patchAffiliateConnectCache(
  userId: string,
  connect: AffiliateConnectRow | null
) {
  const key = userId.trim()
  if (!key) return
  const entry = entryFor(key)
  entry.connect = connect
  entry.fetchedAt = Date.now()
}

export function invalidateAffiliateDataCache(userId?: string | null) {
  if (!userId?.trim()) {
    byViewer.clear()
    return
  }
  byViewer.delete(userId.trim())
}

/** @internal */
export function resetAffiliateDataRepositoryForTests() {
  byViewer.clear()
}

export function isAffiliateDataSoftStale(userId: string): boolean {
  const entry = byViewer.get(userId.trim())
  if (!entry || entry.fetchedAt <= 0) return true
  return Date.now() - entry.fetchedAt > SOFT_STALE_MS
}
