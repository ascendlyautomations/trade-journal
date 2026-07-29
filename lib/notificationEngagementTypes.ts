/** Notification types shown on /notifications and counted in the Navbar badge. */
export const NOTIFICATION_ENGAGEMENT_TYPES = [
  "like",
  "comment",
  "room_join",
  /** Trade Room @mentions only — ordinary room chat is Messaging-only (no Activity row). */
  "room_mention",
  "follow",
  "follow_request",
  "follow_request_accepted",
] as const

export const NOTIFICATION_AFFILIATE_TYPES = [
  "affiliate_referral",
  "affiliate_commission_earned",
] as const

export const NOTIFICATION_TRADING_REPORT_TYPES = ["trading_report"] as const

export const NOTIFICATION_INBOX_TYPES = [
  ...NOTIFICATION_ENGAGEMENT_TYPES,
  ...NOTIFICATION_AFFILIATE_TYPES,
  ...NOTIFICATION_TRADING_REPORT_TYPES,
] as const

export type NotificationEngagementType =
  (typeof NOTIFICATION_ENGAGEMENT_TYPES)[number]

export type NotificationAffiliateType = (typeof NOTIFICATION_AFFILIATE_TYPES)[number]

export type NotificationInboxType = (typeof NOTIFICATION_INBOX_TYPES)[number]
