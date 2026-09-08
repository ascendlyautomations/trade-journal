import type { SupabaseClient } from "@supabase/supabase-js"
import { profilePath } from "./profileRoutes"
import {
  contentReportReasonLabel,
  contentReportTargetLabel,
  type ContentReportRow,
  type ContentReportTargetType,
} from "./contentReports"
import { formatSignedPnlDisplay } from "./formatDisplay"

export type AdminReportProfileSummary = {
  id: string
  username: string | null
  name: string | null
  avatar_url: string | null
  is_banned: boolean
  banned_reason: string | null
  banned_at: string | null
}

export type AdminReportTargetPreview = {
  targetType: ContentReportTargetType
  targetId: string
  headline: string
  subline: string | null
  ownerUserId: string | null
  href: string | null
  viewLabel: "View Content" | "View Profile"
  unavailable: boolean
}

export type AdminContentReportEnrichment = {
  profiles: Record<string, AdminReportProfileSummary>
  targets: Record<string, AdminReportTargetPreview>
}

export type ContentReportRowHydrated = ContentReportRow

const PROFILE_SELECT =
  "id, username, name, avatar_url, is_banned, banned_reason, banned_at"

export function logSupabaseError(
  context: string,
  error: {
    message?: string
    code?: string
    details?: string
    hint?: string
  } | null
) {
  if (!error) return
  console.error(context, {
    message: error.message ?? "(no message)",
    code: error.code ?? "(no code)",
    details: error.details ?? "(no details)",
    hint: error.hint ?? "(no hint)",
  })
}

export function collectReportUserIds(rows: ContentReportRow[]): string[] {
  const ids = new Set<string>()
  for (const row of rows) {
    if (row.reporter_user_id) ids.add(row.reporter_user_id)
    if (row.reported_user_id) ids.add(row.reported_user_id)
    const reported = resolveReportedUserId(row)
    if (reported) ids.add(reported)
    if (row.target_type === "user" && row.target_id.trim()) {
      ids.add(row.target_id.trim())
    }
  }
  return [...ids]
}

export function targetPreviewKey(
  targetType: ContentReportTargetType,
  targetId: string
): string {
  return `${targetType}:${targetId}`
}

export function resolveReportedUserId(row: ContentReportRow): string | null {
  if (row.reported_user_id) return row.reported_user_id
  if (row.target_type === "user") return row.target_id
  return null
}

export function profileHandle(
  profile: Pick<AdminReportProfileSummary, "username" | "id"> | null | undefined
): string {
  if (!profile) return "Unknown user"
  const username = profile.username?.trim()
  if (username) return `@${username}`
  return profile.id.slice(0, 8)
}

export function profileDisplayName(
  profile: Pick<AdminReportProfileSummary, "name" | "username" | "id"> | null | undefined
): string {
  if (!profile) return "Unknown user"
  const name = profile.name?.trim()
  if (name) return name
  const username = profile.username?.trim()
  if (username) return username
  return profile.id.slice(0, 8)
}

function asProfileSummary(raw: unknown): AdminReportProfileSummary | null {
  if (!raw || typeof raw !== "object") return null
  const row = raw as Record<string, unknown>
  const id = typeof row.id === "string" ? row.id : null
  if (!id) return null
  return {
    id,
    username: typeof row.username === "string" ? row.username : null,
    name: typeof row.name === "string" ? row.name : null,
    avatar_url: typeof row.avatar_url === "string" ? row.avatar_url : null,
    is_banned: row.is_banned === true,
    banned_reason: typeof row.banned_reason === "string" ? row.banned_reason : null,
    banned_at: typeof row.banned_at === "string" ? row.banned_at : null,
  }
}

async function fetchProfilesByIds(
  supabase: SupabaseClient,
  ids: string[]
): Promise<Record<string, AdminReportProfileSummary>> {
  const unique = [...new Set(ids.filter(Boolean))]
  if (unique.length === 0) return {}

  const { data, error } = await supabase
    .from("profiles")
    .select(PROFILE_SELECT)
    .in("id", unique)

  if (error) {
    logSupabaseError("[admin-content-reports] profile batch fetch failed", error)
    return {}
  }

  const map: Record<string, AdminReportProfileSummary> = {}
  for (const raw of data ?? []) {
    const profile = asProfileSummary(raw)
    if (profile) map[profile.id] = profile
  }
  return map
}

function ownerHandle(
  ownerUserId: string | null | undefined,
  profiles: Record<string, AdminReportProfileSummary>
): string | null {
  if (!ownerUserId) return null
  return profileHandle(profiles[ownerUserId] ?? { id: ownerUserId, username: null })
}

function buildUserTargetPreview(
  userId: string,
  profiles: Record<string, AdminReportProfileSummary>
): AdminReportTargetPreview {
  const profile = profiles[userId]
  return {
    targetType: "user",
    targetId: userId,
    headline: profileDisplayName(profile ?? { id: userId, username: null, name: null }),
    subline: profile ? profileHandle(profile) : null,
    ownerUserId: userId,
    href: profile ? profilePath(profile) : `/profile/${userId}`,
    viewLabel: "View Profile",
    unavailable: !profile,
  }
}

function buildMissingTargetPreview(row: ContentReportRow): AdminReportTargetPreview {
  return {
    targetType: row.target_type,
    targetId: row.target_id,
    headline: "Deleted content",
    subline: `${contentReportTargetLabel(row.target_type)} may have been removed.`,
    ownerUserId: resolveReportedUserId(row),
    href: null,
    viewLabel: row.target_type === "user" ? "View Profile" : "View Content",
    unavailable: true,
  }
}

async function batchFetchTargetPreviews(
  supabase: SupabaseClient,
  rows: ContentReportRow[],
  profiles: Record<string, AdminReportProfileSummary>
): Promise<Record<string, AdminReportTargetPreview>> {
  const previews: Record<string, AdminReportTargetPreview> = {}
  const idsByType = new Map<ContentReportTargetType, string[]>()

  for (const row of rows) {
    const list = idsByType.get(row.target_type) ?? []
    if (!list.includes(row.target_id)) list.push(row.target_id)
    idsByType.set(row.target_type, list)
  }

  const ownerIds = new Set<string>()

  async function loadTable<T extends { id: string }>(
    table: string,
    ids: string[],
    select: string,
    mapRow: (row: T) => AdminReportTargetPreview
  ) {
    if (ids.length === 0) return
    const { data, error } = await supabase.from(table).select(select).in("id", ids)
    if (error) {
      logSupabaseError(`[admin-content-reports] ${table} batch fetch failed`, error)
      return
    }
    for (const raw of data ?? []) {
      const row = raw as unknown as T
      const preview = mapRow(row)
      previews[targetPreviewKey(preview.targetType, preview.targetId)] = preview
      if (preview.ownerUserId) ownerIds.add(preview.ownerUserId)
    }
  }

  await loadTable(
    "trades",
    idsByType.get("trade") ?? [],
    "id, ticker, pnl, user_id",
    (trade) => {
      const ownerUserId = (trade as { user_id?: string | null }).user_id ?? null
      const handle = ownerHandle(ownerUserId, profiles)
      const pnl = formatSignedPnlDisplay((trade as { pnl?: number | null }).pnl)
      const ticker = ((trade as { ticker?: string | null }).ticker ?? "—").toUpperCase()
      return {
        targetType: "trade",
        targetId: trade.id,
        headline: `${pnl} | ${ticker}`,
        subline: handle ? `Trade · ${handle}` : "Trade",
        ownerUserId,
        href: `/trade/${trade.id}`,
        viewLabel: "View Content",
        unavailable: false,
      }
    }
  )

  await loadTable(
    "posts",
    idsByType.get("post") ?? [],
    "id, caption, user_id",
    (post) => {
      const ownerUserId = (post as { user_id?: string | null }).user_id ?? null
      const caption = ((post as { caption?: string | null }).caption ?? "").trim()
      const handle = ownerHandle(ownerUserId, profiles)
      return {
        targetType: "post",
        targetId: post.id,
        headline: caption ? caption.slice(0, 80) : "Post",
        subline: handle ? `Post · ${handle}` : "Post",
        ownerUserId,
        href: `/post/${post.id}`,
        viewLabel: "View Content",
        unavailable: false,
      }
    }
  )

  await loadTable(
    "reels",
    idsByType.get("reel") ?? [],
    "id, caption, user_id",
    (reel) => {
      const ownerUserId = (reel as { user_id?: string | null }).user_id ?? null
      const caption = ((reel as { caption?: string | null }).caption ?? "").trim()
      const handle = ownerHandle(ownerUserId, profiles)
      return {
        targetType: "reel",
        targetId: reel.id,
        headline: caption ? caption.slice(0, 80) : "Reel",
        subline: handle ? `Reel · ${handle}` : "Reel",
        ownerUserId,
        href: `/reel/${reel.id}`,
        viewLabel: "View Content",
        unavailable: false,
      }
    }
  )

  await loadTable(
    "achievements",
    idsByType.get("achievement") ?? [],
    "id, title, user_id",
    (achievement) => {
      const ownerUserId = (achievement as { user_id?: string | null }).user_id ?? null
      const title = ((achievement as { title?: string | null }).title ?? "Achievement").trim()
      const handle = ownerHandle(ownerUserId, profiles)
      const profile = ownerUserId ? profiles[ownerUserId] : null
      return {
        targetType: "achievement",
        targetId: achievement.id,
        headline: title,
        subline: handle ? `Achievement · ${handle}` : "Achievement",
        ownerUserId,
        href: profile ? `${profilePath(profile)}?tab=achievements` : null,
        viewLabel: "View Content",
        unavailable: false,
      }
    }
  )

  await loadTable(
    "stories",
    idsByType.get("story") ?? [],
    "id, user_id",
    (story) => {
      const ownerUserId = (story as { user_id?: string | null }).user_id ?? null
      const handle = ownerHandle(ownerUserId, profiles)
      return {
        targetType: "story",
        targetId: story.id,
        headline: "Story",
        subline: handle ? `Story · ${handle}` : "Story",
        ownerUserId,
        href: `/story/${story.id}`,
        viewLabel: "View Content",
        unavailable: false,
      }
    }
  )

  await loadTable(
    "comments",
    idsByType.get("comment") ?? [],
    "id, content, user_id, post_id",
    (comment) => {
      const ownerUserId = (comment as { user_id?: string | null }).user_id ?? null
      const content = ((comment as { content?: string | null }).content ?? "").trim()
      const postId = (comment as { post_id?: string | null }).post_id
      const handle = ownerHandle(ownerUserId, profiles)
      return {
        targetType: "comment",
        targetId: comment.id,
        headline: content ? content.slice(0, 80) : "Comment",
        subline: handle ? `Comment · ${handle}` : "Comment",
        ownerUserId,
        href: postId ? `/post/${postId}` : null,
        viewLabel: "View Content",
        unavailable: false,
      }
    }
  )

  await loadTable(
    "direct_messages",
    idsByType.get("direct_message") ?? [],
    "id, content, sender_id, conversation_id",
    (message) => {
      const ownerUserId = (message as { sender_id?: string | null }).sender_id ?? null
      const content = ((message as { content?: string | null }).content ?? "").trim()
      const conversationId = (message as { conversation_id?: string | null }).conversation_id
      const handle = ownerHandle(ownerUserId, profiles)
      return {
        targetType: "direct_message",
        targetId: message.id,
        headline: content ? content.slice(0, 80) : "Direct message",
        subline: handle ? `Direct message · ${handle}` : "Direct message",
        ownerUserId,
        href: conversationId ? `/messages/${conversationId}` : null,
        viewLabel: "View Content",
        unavailable: false,
      }
    }
  )

  await loadTable(
    "rooms",
    idsByType.get("trade_room") ?? [],
    "id, name, owner_user_id, slug",
    (room) => {
      const ownerUserId = (room as { owner_user_id?: string | null }).owner_user_id ?? null
      const name = ((room as { name?: string | null }).name ?? "Trade Room").trim()
      const slug = (room as { slug?: string | null }).slug?.trim()
      const handle = ownerHandle(ownerUserId, profiles)
      return {
        targetType: "trade_room",
        targetId: room.id,
        headline: name,
        subline: handle ? `Trade Room · ${handle}` : "Trade Room",
        ownerUserId,
        href: slug ? `/room/${slug}` : `/room/${room.id}`,
        viewLabel: "View Content",
        unavailable: false,
      }
    }
  )

  await loadTable(
    "room_messages",
    idsByType.get("trade_room_message") ?? [],
    "id, content, user_id, room_id",
    (message) => {
      const ownerUserId = (message as { user_id?: string | null }).user_id ?? null
      const content = ((message as { content?: string | null }).content ?? "").trim()
      const roomId = (message as { room_id?: string | null }).room_id
      const handle = ownerHandle(ownerUserId, profiles)
      return {
        targetType: "trade_room_message",
        targetId: message.id,
        headline: content ? content.slice(0, 80) : "Trade Room message",
        subline: handle ? `Trade Room message · ${handle}` : "Trade Room message",
        ownerUserId,
        href: roomId ? `/room/${roomId}` : null,
        viewLabel: "View Content",
        unavailable: false,
      }
    }
  )

  const userTargetIds = idsByType.get("user") ?? []
  const missingOwnerIds = [...ownerIds].filter((id) => !profiles[id])
  const extraProfileIds = [...new Set([...userTargetIds, ...missingOwnerIds])]
  if (extraProfileIds.length > 0) {
    const extraProfiles = await fetchProfilesByIds(supabase, extraProfileIds)
    Object.assign(profiles, extraProfiles)
  }

  for (const userId of userTargetIds) {
    previews[targetPreviewKey("user", userId)] = buildUserTargetPreview(userId, profiles)
  }

  for (const row of rows) {
    const key = targetPreviewKey(row.target_type, row.target_id)
    if (!previews[key]) {
      if (row.target_type === "user") {
        previews[key] = buildUserTargetPreview(row.target_id, profiles)
      } else {
        previews[key] = buildMissingTargetPreview(row)
      }
    }
  }

  for (const key of Object.keys(previews)) {
    const preview = previews[key]
    if (!preview.ownerUserId || preview.targetType === "user") continue
    const handle = ownerHandle(preview.ownerUserId, profiles)
    if (!handle) continue
    previews[key] = {
      ...preview,
      subline: `${contentReportTargetLabel(preview.targetType)} · ${handle}`,
    }
  }

  return previews
}

export async function hydrateAdminContentReports(
  supabase: SupabaseClient,
  rows: ContentReportRow[]
): Promise<AdminContentReportEnrichment> {
  const profiles: Record<string, AdminReportProfileSummary> = {}

  try {
    Object.assign(profiles, await fetchProfilesByIds(supabase, collectReportUserIds(rows)))
  } catch (err) {
    console.error("[admin-content-reports] profile hydration threw", err)
  }

  let targets: Record<string, AdminReportTargetPreview> = {}
  try {
    targets = await batchFetchTargetPreviews(supabase, rows, profiles)
  } catch (err) {
    console.error("[admin-content-reports] target hydration threw", err)
  }

  for (const row of rows) {
    const key = targetPreviewKey(row.target_type, row.target_id)
    if (!targets[key]) {
      if (row.target_type === "user") {
        targets[key] = buildUserTargetPreview(row.target_id, profiles)
      } else {
        targets[key] = buildMissingTargetPreview(row)
      }
    }
  }

  return { profiles, targets }
}

export function getTargetPreview(
  enrichment: AdminContentReportEnrichment,
  row: ContentReportRow
): AdminReportTargetPreview {
  return (
    enrichment.targets[targetPreviewKey(row.target_type, row.target_id)] ??
    buildMissingTargetPreview(row)
  )
}

export function getProfileSummary(
  enrichment: AdminContentReportEnrichment,
  userId: string | null | undefined
): AdminReportProfileSummary | null {
  if (!userId) return null
  return enrichment.profiles[userId] ?? null
}

export function listReportedSubjectLabel(
  row: ContentReportRow,
  enrichment: AdminContentReportEnrichment
): string {
  const preview = getTargetPreview(enrichment, row)
  if (row.target_type === "user") {
    return profileHandle(getProfileSummary(enrichment, row.target_id))
  }
  const handle = preview.ownerUserId
    ? profileHandle(getProfileSummary(enrichment, preview.ownerUserId))
    : null
  if (handle && preview.headline !== "Post" && preview.headline !== "Reel") {
    return `${contentReportTargetLabel(row.target_type)} · ${handle}`
  }
  if (handle) return `${contentReportTargetLabel(row.target_type)} · ${handle}`
  return preview.headline
}

export function listReporterLabel(
  row: ContentReportRow,
  enrichment: AdminContentReportEnrichment
): string {
  return profileHandle(getProfileSummary(enrichment, row.reporter_user_id))
}

export function moderationStatusLabel(
  profile: AdminReportProfileSummary | null | undefined
): string {
  if (!profile) return "Unknown"
  if (profile.is_banned) return "Banned"
  return "Active"
}

export function suggestedBanReasonFromReport(row: ContentReportRow): string {
  const reason = contentReportReasonLabel(row.reason)
  const details = row.details?.trim()
  return details ? `${reason}: ${details}` : reason
}
