/**
 * Frozen rank session for rpc_v2_feed_bootstrap pagination.
 * Rank pages use score|kind|id; deeper history advances p_scan_cursor (v1 chrono).
 */

export type FeedRotatingSession = {
  sessionId: string
  rankFrozenAt: string
  scanCursor: string | null
  usingV2: boolean
}

const sessions = new Map<string, FeedRotatingSession>()

function randomId(): string {
  if (typeof crypto !== "undefined" && crypto.randomUUID) {
    return crypto.randomUUID()
  }
  return `feed-${Date.now()}-${Math.random().toString(36).slice(2)}`
}

export function feedRotatingSessionKey(
  userId: string,
  scope: string,
  contentFilter: string
): string {
  return `${userId}|${scope}|${contentFilter}`
}

export function feedContentKey(
  feedKind: string,
  contentId: string
): string {
  const kind =
    feedKind === "trade"
      ? "post"
      : feedKind === "profile"
        ? "profile_post"
        : feedKind === "achievement"
          ? "achievement_post"
          : feedKind === "reel"
            ? "reel"
            : feedKind
  return `${kind}|${String(contentId).trim()}`
}

/** Rank pagination cursor (numeric score first segment). */
export function isFeedRankCursor(cursor: string): boolean {
  const parts = cursor.split("|")
  if (parts.length < 3) return false
  return /^-?\d+(\.\d+)?$/.test(parts[0]?.trim() ?? "")
}

export function beginFeedRotatingSession(
  userId: string,
  scope: string,
  contentFilter: string
): FeedRotatingSession {
  const key = feedRotatingSessionKey(userId, scope, contentFilter)
  const existing = sessions.get(key)
  if (existing?.usingV2) {
    return existing
  }
  const session: FeedRotatingSession = {
    sessionId: randomId(),
    rankFrozenAt: new Date().toISOString(),
    scanCursor: null,
    usingV2: true,
  }
  sessions.set(key, session)
  return session
}

export function getFeedRotatingSession(
  userId: string,
  scope: string,
  contentFilter: string
): FeedRotatingSession | null {
  return sessions.get(feedRotatingSessionKey(userId, scope, contentFilter)) ?? null
}

export function setFeedScanCursor(
  userId: string,
  scope: string,
  contentFilter: string,
  scanCursor: string | null
): void {
  const session = getFeedRotatingSession(userId, scope, contentFilter)
  if (!session) return
  session.scanCursor = scanCursor?.trim() || null
}

export function clearFeedRotatingSession(
  userId: string,
  scope: string,
  contentFilter: string
): void {
  sessions.delete(feedRotatingSessionKey(userId, scope, contentFilter))
}

export function resetFeedRotatingSessionForUser(userId: string): void {
  for (const key of sessions.keys()) {
    if (key.startsWith(`${userId}|`)) sessions.delete(key)
  }
}

export function markFeedRotatingV1Fallback(
  userId: string,
  scope: string,
  contentFilter: string
): void {
  sessions.delete(feedRotatingSessionKey(userId, scope, contentFilter))
}