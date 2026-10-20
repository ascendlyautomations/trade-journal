/**
 * Trade Room structured shares — JSON in `room_messages.content`
 * (native `SharedContentRoomMessageSupport`).
 */

export type RoomSharedContentKind =
  | "post"
  | "profile_post"
  | "achievement_post"
  | "reel"
  | "trade"

export type RoomSharedContentReference = {
  kind: RoomSharedContentKind
  postId?: string
  profilePostId?: string
  achievementPostId?: string
  reelId?: string
  tradeId?: string
}

const PLACEHOLDER_SHARE_BODIES = new Set([
  "Shared a trade",
  "Shared a post",
  "Shared a clip",
  "Shared an achievement",
])

function trimId(value: unknown): string | null {
  if (value == null) return null
  const s = String(value).trim()
  return s.length > 0 ? s : null
}

function normalizeShareType(type: unknown): string | null {
  const s = trimId(type)
  return s ? s.toLowerCase() : null
}

export function decodeRoomShareContent(
  content: string | null | undefined
): RoomSharedContentReference | null {
  const raw = content?.trim()
  if (!raw || !raw.startsWith("{")) return null

  let json: Record<string, unknown>
  try {
    const parsed = JSON.parse(raw) as unknown
    if (parsed == null || typeof parsed !== "object" || Array.isArray(parsed)) {
      return null
    }
    json = parsed as Record<string, unknown>
  } catch {
    return null
  }

  const shareType = normalizeShareType(json.share_type)
  return resolveRoomSharedContentReference({
    type: shareType,
    postId: trimId(json.post_id),
    profilePostId: trimId(json.profile_post_id),
    achievementPostId: trimId(json.achievement_post_id),
    reelId: trimId(json.reel_id),
    tradeId: trimId(json.trade_id),
  })
}

export function resolveRoomSharedContentReference(input: {
  type?: string | null
  postId?: string | null
  profilePostId?: string | null
  achievementPostId?: string | null
  reelId?: string | null
  tradeId?: string | null
}): RoomSharedContentReference | null {
  const type = normalizeShareType(input.type)
  const postId = trimId(input.postId)
  const profilePostId = trimId(input.profilePostId)
  const achievementPostId = trimId(input.achievementPostId)
  const reelId = trimId(input.reelId)
  const tradeId = trimId(input.tradeId)

  switch (type) {
    case "post":
      if (postId) return { kind: "post", postId }
      break
    case "profile_post":
      if (profilePostId) return { kind: "profile_post", profilePostId }
      break
    case "achievement_post":
      if (achievementPostId) return { kind: "achievement_post", achievementPostId }
      break
    case "reel":
      if (reelId) return { kind: "reel", reelId }
      break
    case "trade":
      if (tradeId) return { kind: "trade", tradeId }
      break
    default:
      break
  }

  if (tradeId) return { kind: "trade", tradeId }
  if (postId) return { kind: "post", postId }
  if (profilePostId) return { kind: "profile_post", profilePostId }
  if (achievementPostId) return { kind: "achievement_post", achievementPostId }
  if (reelId) return { kind: "reel", reelId }

  return null
}

export function resolveRoomMessageShare(message: {
  type?: string | null
  content?: string | null
  trade_id?: string | null
}): RoomSharedContentReference | null {
  const fromContent = decodeRoomShareContent(message.content)
  const typeNorm = normalizeShareType(message.type)
  const tradeColumn = trimId(message.trade_id)

  if (typeNorm === "trade" || tradeColumn) {
    const tradeId =
      tradeColumn ?? fromContent?.tradeId ?? (fromContent?.kind === "trade" ? fromContent.tradeId : null)
    if (tradeId) {
      return { kind: "trade", tradeId }
    }
  }

  if (
    typeNorm &&
    ["post", "profile_post", "achievement_post", "reel"].includes(typeNorm)
  ) {
    const merged = resolveRoomSharedContentReference({
      type: typeNorm,
      postId: fromContent?.postId,
      profilePostId: fromContent?.profilePostId,
      achievementPostId: fromContent?.achievementPostId,
      reelId: fromContent?.reelId,
      tradeId: fromContent?.tradeId,
    })
    if (merged) return merged
  }

  return fromContent
}

export function isRoomStructuredShareMessage(message: {
  type?: string | null
  content?: string | null
  trade_id?: string | null
}): boolean {
  const typeNorm = normalizeShareType(message.type)
  if (typeNorm === "trade" && trimId(message.trade_id)) return true
  if (
    typeNorm &&
    ["post", "profile_post", "achievement_post", "reel", "trade"].includes(
      typeNorm
    )
  ) {
    return resolveRoomMessageShare(message) != null
  }
  return decodeRoomShareContent(message.content) != null
}

/** Plain-text body when content is not solely a structured share payload. */
export function roomMessageDisplayText(message: {
  type?: string | null
  content?: string | null
  trade_id?: string | null
}): string | null {
  if (isRoomStructuredShareMessage(message)) {
    const trimmed = message.content?.trim() ?? ""
    if (!trimmed || decodeRoomShareContent(trimmed)) return null
    if (PLACEHOLDER_SHARE_BODIES.has(trimmed)) return null
    return trimmed
  }
  const trimmed = message.content?.trim() ?? ""
  return trimmed.length > 0 ? trimmed : null
}

export function roomSharedContentLabel(kind: RoomSharedContentKind): string {
  switch (kind) {
    case "post":
    case "profile_post":
      return "Shared Post"
    case "achievement_post":
      return "Shared Achievement"
    case "reel":
      return "Shared Clip"
    case "trade":
      return "Shared Trade"
    default:
      return "Shared content"
  }
}
