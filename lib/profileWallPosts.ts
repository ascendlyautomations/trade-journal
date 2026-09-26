import type { SupabaseClient } from "@supabase/supabase-js"

/**
 * Profile wall page size. Two-column post grid; 12 matches the existing
 * mobile Profile trades page and fills the grid without loading the wall.
 */
export const PROFILE_WALL_POSTS_PAGE_SIZE = 12

/**
 * Columns the Profile post card, room share, pin, edit, delete, and share
 * actions read. `image_crop` is unused by this UI.
 */
export const PROFILE_WALL_POST_SELECT =
  "id, user_id, content, image_url, created_at, is_pinned, room_id, room_name, room_logo, room_description"

export type ProfileWallPostPageRow = {
  id: string
  user_id?: string | null
  content?: string | null
  image_url?: string | null
  created_at?: string | null
  is_pinned?: boolean | null
  room_id?: string | null
  room_name?: string | null
  room_logo?: string | null
  room_description?: string | null
}

/** Null `createdAt` means the unpinned stream has not started. */
export type ProfileWallPostsCursor = {
  phase: "pinned" | "unpinned"
  createdAt: string | null
  id: string | null
}

type WallOrderRow = {
  id: unknown
  created_at?: unknown
  is_pinned?: unknown
}

function createdAtMs(value: unknown): number {
  if (typeof value !== "string" || !value) return 0
  const ms = new Date(value).getTime()
  return Number.isFinite(ms) ? ms : 0
}

/** Pinned first, then newest created_at, then id descending for equal times. */
export function compareProfileWallPosts(a: WallOrderRow, b: WallOrderRow): number {
  const aPinned = a.is_pinned === true
  const bPinned = b.is_pinned === true
  if (aPinned !== bPinned) return aPinned ? -1 : 1
  const time = createdAtMs(b.created_at) - createdAtMs(a.created_at)
  if (time !== 0) return time
  const aId = String(a.id)
  const bId = String(b.id)
  if (aId === bId) return 0
  return aId < bId ? 1 : -1
}

export function sortProfileWallPosts<T extends WallOrderRow>(rows: T[]): T[] {
  return [...rows].sort(compareProfileWallPosts)
}

export function profileWallPostsBeforeCursorFilter(
  createdAt: string,
  id: string
): string {
  const ts = `"${createdAt}"`
  const rowId = `"${id}"`
  return `created_at.lt.${ts},and(created_at.eq.${ts},id.lt.${rowId})`
}

export function canStartProfileWallPostsLoad(input: {
  inFlight: boolean
  hasMore: boolean
  mode: "initial" | "more"
}): boolean {
  if (input.inFlight) return false
  if (input.mode === "more") return input.hasMore
  return true
}

export function isCurrentProfileWallPostsRequest(
  requestProfileId: string,
  currentProfileId: string | null | undefined
): boolean {
  return (
    currentProfileId != null &&
    String(requestProfileId) === String(currentProfileId)
  )
}

function cursorFromRow(
  phase: "pinned" | "unpinned",
  row: WallOrderRow | undefined
): ProfileWallPostsCursor | null {
  if (!row) return null
  return {
    phase,
    createdAt: typeof row.created_at === "string" ? row.created_at : null,
    id: String(row.id),
  }
}

export function sliceProfileWallPostsPage<T extends WallOrderRow>(
  all: T[],
  cursor: ProfileWallPostsCursor | null,
  pageSize = PROFILE_WALL_POSTS_PAGE_SIZE
): {
  rows: T[]
  hasMore: boolean
  cursor: ProfileWallPostsCursor | null
} {
  const ordered = sortProfileWallPosts(all)
  const pinned = ordered.filter((row) => row.is_pinned === true)
  const unpinned = ordered.filter((row) => row.is_pinned !== true)

  const after = (rows: T[], createdAt: string | null, id: string | null) => {
    if (!createdAt || !id) return rows
    const index = rows.findIndex(
      (row) =>
        (typeof row.created_at === "string" ? row.created_at : null) ===
          createdAt && String(row.id) === id
    )
    return index === -1 ? rows : rows.slice(index + 1)
  }

  if (!cursor || cursor.phase === "pinned") {
    const pinnedRest =
      cursor?.phase === "pinned"
        ? after(pinned, cursor.createdAt, cursor.id)
        : pinned
    const pinnedPage = pinnedRest.slice(0, pageSize)
    if (pinnedRest.length > pageSize) {
      return {
        rows: pinnedPage,
        hasMore: true,
        cursor: cursorFromRow("pinned", pinnedPage[pinnedPage.length - 1]),
      }
    }
    const need = pageSize - pinnedPage.length
    if (need === 0) {
      return {
        rows: pinnedPage,
        hasMore: unpinned.length > 0,
        cursor:
          unpinned.length > 0
            ? { phase: "unpinned", createdAt: null, id: null }
            : cursorFromRow("pinned", pinnedPage[pinnedPage.length - 1]),
      }
    }
    const unpinnedPage = unpinned.slice(0, need)
    const rows = [...pinnedPage, ...unpinnedPage]
    const hasMore = unpinned.length > need
    const tailPhase = unpinnedPage.length > 0 ? "unpinned" : "pinned"
    return {
      rows,
      hasMore,
      cursor: cursorFromRow(tailPhase, rows[rows.length - 1]),
    }
  }

  const unpinnedRest = after(unpinned, cursor.createdAt, cursor.id)
  const page = unpinnedRest.slice(0, pageSize)
  return {
    rows: page,
    hasMore: unpinnedRest.length > pageSize,
    cursor: cursorFromRow("unpinned", page[page.length - 1] ?? undefined),
  }
}

export function mergeProfileWallPosts<T extends { id: string }>(
  existing: T[],
  incoming: T[]
): T[] {
  const seen = new Set(existing.map((row) => String(row.id)))
  const next = [...existing]
  for (const row of incoming) {
    const id = String(row.id)
    if (seen.has(id)) continue
    seen.add(id)
    next.push(row)
  }
  return next
}

export function upsertProfileWallPost<T extends WallOrderRow>(
  posts: T[],
  post: T
): T[] {
  const rest = posts.filter((row) => String(row.id) !== String(post.id))
  return sortProfileWallPosts([post, ...rest])
}

export function removeProfileWallPost<T extends { id: string }>(
  posts: T[],
  postId: string
): T[] {
  return posts.filter((row) => String(row.id) !== String(postId))
}

export function patchProfileWallPost<T extends { id: string }>(
  posts: T[],
  postId: string,
  patch: Partial<T>
): T[] {
  return posts.map((row) =>
    String(row.id) === String(postId) ? { ...row, ...patch } : row
  )
}

async function fetchProfileWallPostStream(
  client: SupabaseClient,
  userId: string,
  stream: "pinned" | "unpinned",
  after: { createdAt: string; id: string } | null,
  limit: number
): Promise<ProfileWallPostPageRow[]> {
  let query = client
    .from("profile_posts")
    .select(PROFILE_WALL_POST_SELECT)
    .eq("user_id", userId)

  query =
    stream === "pinned"
      ? query.eq("is_pinned", true)
      : query.not("is_pinned", "is", true)

  if (after) {
    query = query.or(
      profileWallPostsBeforeCursorFilter(after.createdAt, after.id)
    )
  }

  const { data, error } = await query
    .order("created_at", { ascending: false })
    .order("id", { ascending: false })
    .limit(limit)

  if (error) throw error
  return (data ?? []) as ProfileWallPostPageRow[]
}

export async function fetchProfileWallPostsPage(
  client: SupabaseClient,
  userId: string,
  cursor: ProfileWallPostsCursor | null,
  pageSize = PROFILE_WALL_POSTS_PAGE_SIZE
): Promise<{
  rows: ProfileWallPostPageRow[]
  hasMore: boolean
  cursor: ProfileWallPostsCursor | null
}> {
  const probe = pageSize + 1

  if (!cursor || cursor.phase === "pinned") {
    const after =
      cursor?.phase === "pinned" && cursor.createdAt && cursor.id
        ? { createdAt: cursor.createdAt, id: cursor.id }
        : null
    const pinned = await fetchProfileWallPostStream(
      client,
      userId,
      "pinned",
      after,
      probe
    )
    const pinnedPage = pinned.slice(0, pageSize)
    if (pinned.length > pageSize) {
      return {
        rows: pinnedPage,
        hasMore: true,
        cursor: cursorFromRow("pinned", pinnedPage[pinnedPage.length - 1]),
      }
    }

    const need = pageSize - pinnedPage.length
    if (need === 0) {
      const unpinnedProbe = await fetchProfileWallPostStream(
        client,
        userId,
        "unpinned",
        null,
        1
      )
      return {
        rows: pinnedPage,
        hasMore: unpinnedProbe.length > 0,
        cursor:
          unpinnedProbe.length > 0
            ? { phase: "unpinned", createdAt: null, id: null }
            : cursorFromRow("pinned", pinnedPage[pinnedPage.length - 1]),
      }
    }

    const unpinned = await fetchProfileWallPostStream(
      client,
      userId,
      "unpinned",
      null,
      need + 1
    )
    const unpinnedPage = unpinned.slice(0, need)
    const rows = [...pinnedPage, ...unpinnedPage]
    const tailPhase = unpinnedPage.length > 0 ? "unpinned" : "pinned"
    return {
      rows,
      hasMore: unpinned.length > need,
      cursor: cursorFromRow(tailPhase, rows[rows.length - 1]),
    }
  }

  const after =
    cursor.createdAt && cursor.id
      ? { createdAt: cursor.createdAt, id: cursor.id }
      : null
  const unpinned = await fetchProfileWallPostStream(
    client,
    userId,
    "unpinned",
    after,
    probe
  )
  const page = unpinned.slice(0, pageSize)
  return {
    rows: page,
    hasMore: unpinned.length > pageSize,
    cursor: cursorFromRow("unpinned", page[page.length - 1]),
  }
}

export async function fetchProfileWallPostById(
  client: SupabaseClient,
  userId: string,
  postId: string
): Promise<ProfileWallPostPageRow | null> {
  const { data, error } = await client
    .from("profile_posts")
    .select(PROFILE_WALL_POST_SELECT)
    .eq("user_id", userId)
    .eq("id", postId)
    .maybeSingle()

  if (error) throw error
  return (data as ProfileWallPostPageRow | null) ?? null
}
