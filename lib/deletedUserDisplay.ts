export const DELETED_USER_LABEL = "Deleted User"

export type DmSenderDisplay = {
  userId: string | null
  username: string
  isDeleted: boolean
  profileLinkEnabled: boolean
}

/** 1:1 thread where the other participant deleted their account. */
export function isDirectConversationPeerDeleted(
  isGroup: boolean,
  otherProfileUsername: string | null | undefined,
  hasConversationHistory: boolean
): boolean {
  return (
    !isGroup &&
    hasConversationHistory &&
    !otherProfileUsername?.trim()
  )
}

export const ORPHANED_DM_HIDDEN_EVENT = "tj-orphaned-dm-hidden"

/**
 * Confirmed permanent deletion of the other person in a 1:1 chat.
 * Account deletion removes that user's conversation_participants row and
 * leaves the viewer. A missing profile, avatar, or username is not enough:
 * the other participant row must be absent while the viewer is still present.
 * An empty participant list is treated as incomplete data, not deletion.
 */
export function isOrphanedDirectConversation(
  isGroup: boolean,
  participants: Array<{ user_id?: string | null }> | null | undefined,
  viewerUserId: string | null | undefined
): boolean {
  if (isGroup) return false
  const viewer = viewerUserId?.trim() ?? ""
  if (!viewer || !participants?.length) return false
  const ids = participants
    .map((participant) => String(participant?.user_id ?? "").trim())
    .filter((id) => id.length > 0)
  if (!ids.includes(viewer)) return false
  return !ids.some((id) => id !== viewer)
}

type MessageSenderFields = {
  sender_id?: string | null
  sender_anonymized?: boolean | null
  is_system?: boolean | null
  profiles?:
    | { username?: string | null; avatar_url?: string | null }
    | { username?: string | null; avatar_url?: string | null }[]
    | null
}

function resolveProfileUsername(
  profiles: MessageSenderFields["profiles"]
): string | null {
  if (!profiles) return null
  const row = Array.isArray(profiles) ? profiles[0] : profiles
  const username = row?.username?.trim()
  return username || null
}

/** Resolve DM sender label + whether profile navigation is allowed. */
export function resolveDmSenderDisplay(
  message: MessageSenderFields,
  fallback = "User"
): DmSenderDisplay {
  if (message.sender_anonymized === true) {
    return {
      userId: null,
      username: DELETED_USER_LABEL,
      isDeleted: true,
      profileLinkEnabled: false,
    }
  }

  const profileUsername = resolveProfileUsername(message.profiles)
  const senderId = message.sender_id?.trim() || null

  if (!senderId) {
    if (message.is_system) {
      return {
        userId: null,
        username: fallback,
        isDeleted: false,
        profileLinkEnabled: false,
      }
    }
    return {
      userId: null,
      username: DELETED_USER_LABEL,
      isDeleted: true,
      profileLinkEnabled: false,
    }
  }

  if (!profileUsername) {
    return {
      userId: null,
      username: DELETED_USER_LABEL,
      isDeleted: true,
      profileLinkEnabled: false,
    }
  }

  return {
    userId: senderId,
    username: profileUsername,
    isDeleted: false,
    profileLinkEnabled: true,
  }
}
