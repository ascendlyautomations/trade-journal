import {
  formatESTDate,
  formatESTTime,
  getESTDateKey,
} from "@/lib/formatDate"

function subtractOneDayFromDateKey(ymd: string): string {
  const [ys, ms, ds] = ymd.split("-").map(Number)
  if (!ys || !ms || !ds) return ""
  const d = new Date(Date.UTC(ys, ms - 1, ds))
  d.setUTCDate(d.getUTCDate() - 1)
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}-${String(d.getUTCDate()).padStart(2, "0")}`
}

/** Divider label for DM day separators (America/New_York). */
export function formatConversationDateDividerLabel(
  dateString: string | null | undefined,
  now = new Date()
): string {
  const messageKey = getESTDateKey(dateString)
  if (!messageKey) return ""

  const todayKey = getESTDateKey(now.toISOString())
  if (messageKey === todayKey) return "Today"

  const yesterdayKey = subtractOneDayFromDateKey(todayKey)
  if (messageKey === yesterdayKey) return "Yesterday"

  return formatESTDate(dateString)
}

/** Time-only label for DM cluster timestamps (e.g. 10:42 PM). */
export function formatDmClusterTime(
  dateString: string | null | undefined
): string {
  return formatESTTime(dateString)
}

type DmMessageLike = {
  is_system?: boolean | null
  sender_id?: string | null
  created_at?: string | null
}

export function shouldShowDmDateDivider(
  messages: DmMessageLike[],
  index: number
): boolean {
  const message = messages[index]
  if (message?.is_system || !message?.created_at) return false

  const messageKey = getESTDateKey(message.created_at)
  if (!messageKey) return false

  for (let j = index - 1; j >= 0; j--) {
    const prev = messages[j]
    if (prev?.is_system) continue
    if (!prev?.created_at) return true
    return getESTDateKey(prev.created_at) !== messageKey
  }

  return true
}

export function shouldShowDmClusterTimestamp(
  messages: DmMessageLike[],
  index: number
): boolean {
  const message = messages[index]
  if (message?.is_system) return false

  const prevMessage = messages[index - 1]
  const nextMessage = messages[index + 1]

  const isNewSender =
    !prevMessage ||
    prevMessage.is_system ||
    prevMessage.sender_id !== message.sender_id

  const isLastInCluster =
    !nextMessage ||
    nextMessage.is_system ||
    nextMessage.sender_id !== message.sender_id

  return isNewSender || isLastInCluster
}
