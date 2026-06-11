/** Notification types shown on /notifications and counted in the Navbar badge. */
export const NOTIFICATION_ENGAGEMENT_TYPES = [
  "like",
  "comment",
  "room_join",
  "follow",
] as const

export type NotificationEngagementType =
  (typeof NOTIFICATION_ENGAGEMENT_TYPES)[number]
