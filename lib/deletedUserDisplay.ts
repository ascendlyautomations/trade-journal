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
