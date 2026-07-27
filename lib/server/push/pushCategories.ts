/** iOS UNNotificationCategory identifiers registered in AppDelegate. */
export const PUSH_CATEGORY = {
  DM: "TT_DM",
  ROOM: "TT_ROOM",
  COMMENT: "TT_COMMENT",
  FOLLOW_REQUEST: "TT_FOLLOW_REQUEST",
} as const

export const PUSH_ACTION = {
  REPLY: "TT_REPLY",
  MARK_READ: "TT_MARK_READ",
  OPEN_ROOM: "TT_OPEN_ROOM",
  VIEW_COMMENT: "TT_VIEW_COMMENT",
  ACCEPT_FOLLOW: "TT_ACCEPT_FOLLOW",
  DECLINE_FOLLOW: "TT_DECLINE_FOLLOW",
} as const

export function categoryForNotificationType(type: string): string | undefined {
  switch (type) {
    case "message":
      return PUSH_CATEGORY.DM
    case "room_message":
    case "room_mention":
      return PUSH_CATEGORY.ROOM
    case "comment":
      return PUSH_CATEGORY.COMMENT
    case "follow_request":
      return PUSH_CATEGORY.FOLLOW_REQUEST
    default:
      return undefined
  }
}
