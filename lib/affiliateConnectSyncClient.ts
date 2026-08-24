import type { AffiliateConnectRow } from "./affiliateStripeConnect.ts"
import { supabaseBearerHeaders } from "./supabaseBearerFetch.ts"
import { patchAffiliateConnectCache } from "./affiliateDataRepository.ts"

const SYNC_SUCCESS_TTL_MS = 120_000
const SYNC_FAILURE_TTL_MS = 300_000

type SyncSuccessEntry = {
  affiliate: AffiliateConnectRow | null
  syncedAt: number
}

type SyncFailureEntry = {
  category: string
  error: string
  status: number
  retryable: boolean
  failedAt: number
}

type SyncFlight = {
  promise: Promise<AffiliateConnectSyncResult>
}

export type AffiliateConnectSyncResult = {
  ok: boolean
  skipped: boolean
  affiliate: AffiliateConnectRow | null
  error: string | null
  status: number
  retryable: boolean
  category: string | null
}

const successByViewer = new Map<string, SyncSuccessEntry>()
const failureByViewer = new Map<string, SyncFailureEntry>()
const inflightByViewer = new Map<string, SyncFlight>()

const DETERMINISTIC_FAILURE_CATEGORIES = new Set([
  "stripe_not_configured",
  "stripe_invalid_format",
  "stripe_auth_invalid",
  "stripe_account_missing",
  "stripe_deterministic",
  "affiliate_missing",
])

function recentSuccess(userId: string): SyncSuccessEntry | null {
  const hit = successByViewer.get(userId.trim())
  if (!hit) return null
  if (Date.now() - hit.syncedAt > SYNC_SUCCESS_TTL_MS) {
    successByViewer.delete(userId.trim())
    return null
  }
  return hit
}

export function invalidateAffiliateConnectSyncCache(userId?: string | null) {
  if (!userId?.trim()) {
    successByViewer.clear()
    failureByViewer.clear()
    inflightByViewer.clear()
    return
  }
  const key = userId.trim()
  successByViewer.delete(key)
  failureByViewer.delete(key)
  inflightByViewer.delete(key)
}

/** @internal */
export function resetAffiliateConnectSyncClientForTests() {
  successByViewer.clear()
  failureByViewer.clear()
  inflightByViewer.clear()
}

function recentFailure(userId: string): SyncFailureEntry | null {
  const hit = failureByViewer.get(userId.trim())
  if (!hit) return null
  if (Date.now() - hit.failedAt > SYNC_FAILURE_TTL_MS) {
    failureByViewer.delete(userId.trim())
    return null
  }
  return hit
}

function parseSyncResponse(
  status: number,
  body: Record<string, unknown>
): AffiliateConnectSyncResult {
  const affiliate =
    body.affiliate && typeof body.affiliate === "object"
      ? (body.affiliate as AffiliateConnectRow)
      : null
  const skipped = body.skipped === true
  const ok = body.ok === true || (status >= 200 && status < 300 && !body.error)
  const error =
    typeof body.error === "string" && body.error.trim()
      ? body.error.trim()
      : null
  const retryable = body.retryable === true
  const category =
    typeof body.category === "string" && body.category.trim()
      ? body.category.trim()
      : null
  return {
    ok,
    skipped,
    affiliate,
    error,
    status,
    retryable,
    category,
  }
}

async function runSync(userId: string): Promise<AffiliateConnectSyncResult> {
  const cached = recentSuccess(userId)
  if (cached) {
    return {
      ok: true,
      skipped: true,
      affiliate: cached.affiliate,
      error: null,
      status: 200,
      retryable: false,
      category: null,
    }
  }

  const res = await fetch("/api/affiliates/connect/sync", {
    method: "POST",
    credentials: "include",
    headers: {
      ...(await supabaseBearerHeaders()),
    },
  })

  const body = (await res.json().catch(() => ({}))) as Record<string, unknown>
  const parsed = parseSyncResponse(res.status, body)

  if (parsed.ok && parsed.affiliate) {
    patchAffiliateConnectCache(userId, parsed.affiliate)
    successByViewer.set(userId.trim(), {
      affiliate: parsed.affiliate,
      syncedAt: Date.now(),
    })
    failureByViewer.delete(userId.trim())
  } else if (
    !parsed.ok &&
    parsed.category &&
    DETERMINISTIC_FAILURE_CATEGORIES.has(parsed.category)
  ) {
    failureByViewer.set(userId.trim(), {
      category: parsed.category,
      error: parsed.error ?? "Sync failed",
      status: parsed.status,
      retryable: false,
      failedAt: Date.now(),
    })
  }

  return parsed
}

/**
 * Stripe Connect status sync — one in-flight attempt per viewer.
 * Skips when a recent successful sync is cached unless `force`.
 */
export async function syncAffiliateConnectStatus(
  userId: string,
  options?: { force?: boolean }
): Promise<AffiliateConnectSyncResult> {
  const key = userId.trim()
  if (!key) {
    return {
      ok: false,
      skipped: true,
      affiliate: null,
      error: "Missing viewer",
      status: 400,
      retryable: false,
      category: null,
    }
  }

  if (!options?.force) {
    const cached = recentSuccess(key)
    if (cached) {
      return {
        ok: true,
        skipped: true,
        affiliate: cached.affiliate,
        error: null,
        status: 200,
        retryable: false,
        category: "cached_success",
      }
    }
    const failed = recentFailure(key)
    if (failed && !failed.retryable) {
      return {
        ok: false,
        skipped: failed.category === "stripe_not_configured",
        affiliate: null,
        error: failed.error,
        status: failed.status,
        retryable: false,
        category: failed.category,
      }
    }
    const existing = inflightByViewer.get(key)
    if (existing) return existing.promise
  }

  const flight: SyncFlight = {
    promise: runSync(key).finally(() => {
      const current = inflightByViewer.get(key)
      if (current?.promise === flight.promise) {
        inflightByViewer.delete(key)
      }
    }),
  }
  inflightByViewer.set(key, flight)
  return flight.promise
}
