/** Action row directly under detail-modal media (left column / mobile stack). */
export const DETAIL_MODAL_MEDIA_ACTIONS_CLASS =
  "shrink-0 border-t border-white/10 px-4 py-2"

/** Right-column engagement when media lives in the left column (mobile comment focus hides media stack). */
export function detailModalEngagementInPanel(
  hasMedia: boolean,
  commentsFocused: boolean,
  isMobile: boolean
): boolean {
  if (!hasMedia) return true
  return commentsFocused && isMobile
}
