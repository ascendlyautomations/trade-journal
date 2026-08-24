/**
 * Safe public Profile header preview — navigation seed only, not authorization.
 */

const GLOBAL_KEY = Symbol.for("tradetraxs.profilePreview.cache")
const PREVIEW_TTL_MS = 30 * 60_000

export type ProfileHeaderPreview = {
  id: string
  username?: string | null
  name?: string | null
  avatar_url?: string | null
  /** Only when already visible to the viewer (e.g. feed public row). */
  is_private?: boolean | null
  fetchedAt: number
}

type PreviewStore = {
  bySegment: Map<string, ProfileHeaderPreview>
}

function store(): PreviewStore {
  const g = globalThis as typeof globalThis & { [GLOBAL_KEY]?: PreviewStore }
  if (!g[GLOBAL_KEY]) g[GLOBAL_KEY] = { bySegment: new Map() }
  return g[GLOBAL_KEY]
}

function normalizeSegment(segment: string): string {
  return segment.trim().toLowerCase()
}

export function writeProfileHeaderPreview(
  segment: string,
  preview: Omit<ProfileHeaderPreview, "fetchedAt">
): void {
  const key = normalizeSegment(segment)
  if (!key || !preview.id) return
  store().bySegment.set(key, { ...preview, fetchedAt: Date.now() })
  const idKey = normalizeSegment(String(preview.id))
  if (idKey !== key) {
    store().bySegment.set(idKey, { ...preview, fetchedAt: Date.now() })
  }
}

export function readProfileHeaderPreview(
  segment: string
): ProfileHeaderPreview | null {
  const key = normalizeSegment(segment)
  if (!key) return null
  const entry = store().bySegment.get(key)
  if (!entry) return null
  if (Date.now() - entry.fetchedAt > PREVIEW_TTL_MS) {
    store().bySegment.delete(key)
    return null
  }
  return entry
}

export function clearProfilePreviewCache(): void {
  store().bySegment.clear()
}

/** @internal */
export function __resetProfilePreviewCacheForTests(): void {
  clearProfilePreviewCache()
}
