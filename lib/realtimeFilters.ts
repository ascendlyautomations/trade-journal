/** Max ids for a single Realtime `in.(...)` filter (URL / filter size safety). */
export const REALTIME_IN_FILTER_MAX_IDS = 100

export type RealtimeInFilterResolution =
  | { status: "ready"; filter: string }
  | { status: "empty" }
  | { status: "too_many"; idCount: number; maxIds: number }

export function uniqueSortedRealtimeIds(ids: readonly string[]): string[] {
  return [
    ...new Set(
      ids
        .map((id) => String(id ?? "").trim())
        .filter((id) => id.length > 0)
    ),
  ].sort()
}

function formatRealtimeInFilter(column: string, ids: readonly string[]): string {
  return `${column}=in.(${ids.join(",")})`
}

/**
 * Classify one `in.(...)` filter.
 * `empty` and `too_many` are not filters. Callers must not subscribe without one.
 */
export function resolveRealtimeInFilter(
  column: string,
  ids: readonly string[],
  maxIds = REALTIME_IN_FILTER_MAX_IDS
): RealtimeInFilterResolution {
  const unique = uniqueSortedRealtimeIds(ids)
  if (unique.length === 0) return { status: "empty" }
  if (unique.length > maxIds) {
    return { status: "too_many", idCount: unique.length, maxIds }
  }
  return { status: "ready", filter: formatRealtimeInFilter(column, unique) }
}

/**
 * One filter when the id list fits. `null` means empty or too many ids.
 * It is not permission to subscribe without a filter.
 */
export function buildRealtimeInFilter(
  column: string,
  ids: readonly string[],
  maxIds = REALTIME_IN_FILTER_MAX_IDS
): string | null {
  const resolved = resolveRealtimeInFilter(column, ids, maxIds)
  return resolved.status === "ready" ? resolved.filter : null
}

/** Split ids into bounded groups. Never emits an unbounded "subscribe to all" group. */
export function chunkRealtimeIds(
  ids: readonly string[],
  maxIds = REALTIME_IN_FILTER_MAX_IDS
): string[][] {
  const unique = uniqueSortedRealtimeIds(ids)
  if (unique.length === 0 || maxIds < 1) return []
  const chunks: string[][] = []
  for (let index = 0; index < unique.length; index += maxIds) {
    chunks.push(unique.slice(index, index + maxIds))
  }
  return chunks
}

/**
 * One filtered `in.(...)` string per chunk.
 * Empty input returns []. Oversized input stays filtered. Never returns an unfiltered subscription.
 */
export function buildRealtimeInFilterChunks(
  column: string,
  ids: readonly string[],
  maxIds = REALTIME_IN_FILTER_MAX_IDS
): string[] {
  return chunkRealtimeIds(ids, maxIds).map((chunk) =>
    formatRealtimeInFilter(column, chunk)
  )
}

export function stableIdKey(ids: readonly string[]): string {
  return uniqueSortedRealtimeIds(ids).join(",")
}
