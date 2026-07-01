/** Notification types shown on /notifications and counted in the Navbar badge. */
export const NOTIFICATION_ENGAGEMENT_TYPES = [
  "like",
  "comment",
  "room_join",
  "room_message",
  "follow",
  "follow_request",
] as const

export const NOTIFICATION_AFFILIATE_TYPES = [
  "affiliate_referral",
  "affiliate_commission_earned",
] as const

export const NOTIFICATION_INBOX_TYPES = [
  ...NOTIFICATION_ENGAGEMENT_TYPES,
  ...NOTIFICATION_AFFILIATE_TYPES,
] as const

export type NotificationEngagementType =
  (typeof NOTIFICATION_ENGAGEMENT_TYPES)[number]

export type NotificationAffiliateType = (typeof NOTIFICATION_AFFILIATE_TYPES)[number]

export type NotificationInboxType = (typeof NOTIFICATION_INBOX_TYPES)[number]
