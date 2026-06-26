/** Trade likes + comments cache per trade id (trade detail / social layer). */

const DEFAULT_STALE_MS = 5 * 60 * 1000

export type TradeSocialSnapshot = {
  tradeId: string
  likes: number
  liked: boolean
  comments: any[]
  fetchedAt: number
}

const sessions = new Map<string, TradeSocialSnapshot>()

export function readTradeSocial(tradeId: string): TradeSocialSnapshot | null {
  const key = String(tradeId).trim()
  if (!key) return null
  const entry = sessions.get(key)
  if (!entry) return null
  if (Date.now() - entry.fetchedAt > DEFAULT_STALE_MS) {
    sessions.delete(key)
    return null
  }
  return entry
}

export function writeTradeSocial(
  tradeId: string,
  snapshot: Omit<TradeSocialSnapshot, "tradeId" | "fetchedAt">
) {
  const key = String(tradeId).trim()
  if (!key) return
  sessions.set(key, {
    ...snapshot,
    tradeId: key,
    fetchedAt: Date.now(),
  })
}

export function patchTradeSocialComments(tradeId: string, comments: any[]) {
  const key = String(tradeId).trim()
  const prev = sessions.get(key)
  if (!prev) return
  sessions.set(key, { ...prev, comments, fetchedAt: Date.now() })
}

export function appendTradeSocialComment(tradeId: string, comment: any) {
  const key = String(tradeId).trim()
  const prev = sessions.get(key)
  if (!prev) return
  if (prev.comments.some((c) => c.id === comment.id)) return
  sessions.set(key, {
    ...prev,
    comments: [...prev.comments, comment],
    fetchedAt: Date.now(),
  })
}

export function patchTradeSocialLikes(
  tradeId: string,
  likes: number,
  liked: boolean
) {
  const key = String(tradeId).trim()
  const prev = sessions.get(key)
  if (!prev) return
  sessions.set(key, { ...prev, likes, liked, fetchedAt: Date.now() })
}

export function invalidateTradeSocial(tradeId: string) {
  sessions.delete(String(tradeId).trim())
}
