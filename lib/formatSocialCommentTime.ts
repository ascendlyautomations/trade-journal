import { formatSocialTimestamp } from "@/lib/formatRelativeTime"

/** @deprecated Use formatSocialTimestamp — kept for existing imports. */
export function formatSocialCommentTime(
  dateString: string | null | undefined,
  now = new Date()
): string {
  if (!dateString) return ""
  return formatSocialTimestamp(dateString, now)
}
