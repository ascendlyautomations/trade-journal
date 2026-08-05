/** Max ids for a single Realtime `in.(...)` filter (URL / filter size safety). */
export const REALTIME_IN_FILTER_MAX_IDS = 100

/**
 * Build a postgres_changes `column=in.(id1,id2,…)` filter, or null when empty /
 * too large (caller should fall back to unfiltered + client gate).
 */
export function buildRealtimeInFilter(
  column: string,
  ids: readonly string[],
  maxIds = REALTIME_IN_FILTER_MAX_IDS
): string | null {
  const unique = [
    ...new Set(
      ids
        .map((id) => String(id ?? "").trim())
        .filter((id) => id.length > 0)
    ),
  ].sort()
  if (unique.length === 0) return null
  if (unique.length > maxIds) return null
  return `${column}=in.(${unique.join(",")})`
}

export function stableIdKey(ids: readonly string[]): string {
  return [
    ...new Set(
      ids
        .map((id) => String(id ?? "").trim())
        .filter((id) => id.length > 0)
    ),
  ]
    .sort()
    .join(",")
}
