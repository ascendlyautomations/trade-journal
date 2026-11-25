export const COMMENT_PRIVATE_TRADE_DISCLAIMER =
  "Private trade — anyone who can view this comment can open the attached trade."

export function commentSharedTradeId(comment: {
  shared_trade_id?: string | null
}): string | null {
  const raw = comment?.shared_trade_id
  if (raw == null) return null
  const id = String(raw).trim()
  return id.length > 0 ? id : null
}

export function canPostCommentWithAttachment(
  text: string,
  sharedTradeId: string | null | undefined
): boolean {
  if (sharedTradeId && String(sharedTradeId).trim()) return true
  return Boolean(String(text ?? "").trim())
}

export function isPrivateTradeRow(trade: {
  is_public?: boolean | null
}): boolean {
  return trade.is_public !== true
}