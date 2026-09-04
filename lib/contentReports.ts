export const CONTENT_REPORT_TARGET_TYPES = [
  "user",
  "trade",
  "post",
  "reel",
  "story",
  "achievement",
  "comment",
  "direct_message",
  "trade_room",
  "trade_room_message",
] as const

export type ContentReportTargetType = (typeof CONTENT_REPORT_TARGET_TYPES)[number]

export const CONTENT_REPORT_REASONS = [
  "harassment",
  "spam",
  "scam",
  "inappropriate",
  "hate",
  "impersonation",
  "dangerous",
  "other",
] as const

export type ContentReportReason = (typeof CONTENT_REPORT_REASONS)[number]

export const CONTENT_REPORT_STATUSES = [
  "open",
  "reviewing",
  "resolved",
  "dismissed",
] as const

export type ContentReportStatus = (typeof CONTENT_REPORT_STATUSES)[number]

export type ContentReportRow = {
  id: string
  reporter_user_id: string
  target_type: ContentReportTargetType
  target_id: string
  reported_user_id: string | null
  reason: ContentReportReason
  details: string | null
  status: ContentReportStatus
  created_at: string
  reviewed_at: string | null
  reviewed_by: string | null
}

export function contentReportReasonLabel(reason: ContentReportReason): string {
  switch (reason) {
    case "harassment":
      return "Harassment or bullying"
    case "spam":
      return "Spam"
    case "scam":
      return "Scam or fraud"
    case "inappropriate":
      return "Inappropriate content"
    case "hate":
      return "Hate or abusive content"
    case "impersonation":
      return "Impersonation"
    case "dangerous":
      return "Dangerous content"
    case "other":
      return "Other"
    default:
      return reason
  }
}

export function contentReportTargetLabel(type: ContentReportTargetType): string {
  switch (type) {
    case "user":
      return "User"
    case "trade":
      return "Trade"
    case "post":
      return "Post"
    case "reel":
      return "Reel"
    case "story":
      return "Story"
    case "achievement":
      return "Achievement"
    case "comment":
      return "Comment"
    case "direct_message":
      return "Direct message"
    case "trade_room":
      return "Trade Room"
    case "trade_room_message":
      return "Trade Room message"
    default:
      return type
  }
}

export function contentReportStatusLabel(status: ContentReportStatus): string {
  switch (status) {
    case "open":
      return "Open"
    case "reviewing":
      return "Reviewing"
    case "resolved":
      return "Resolved"
    case "dismissed":
      return "Dismissed"
    default:
      return status
  }
}

export function isContentReportTargetType(
  value: string
): value is ContentReportTargetType {
  return (CONTENT_REPORT_TARGET_TYPES as readonly string[]).includes(value)
}

export function isContentReportReason(value: string): value is ContentReportReason {
  return (CONTENT_REPORT_REASONS as readonly string[]).includes(value)
}

export function isContentReportStatus(value: string): value is ContentReportStatus {
  return (CONTENT_REPORT_STATUSES as readonly string[]).includes(value)
}
