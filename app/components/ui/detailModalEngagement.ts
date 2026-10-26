/** Left column: media + actions stack padding/gap. */
export const DETAIL_MODAL_MEDIA_COLUMN_STACK_CLASS =
  "flex shrink-0 flex-col gap-0 p-1"

/** Wrapper under media in left column / mobile media stack. */
export const DETAIL_MODAL_MEDIA_ACTIONS_WRAP_CLASS =
  "shrink-0 border-b border-white/10 px-4 py-0.5"

/** Engagement row in the right panel when media sits in the left column. */
export const DETAIL_MODAL_PANEL_ENGAGEMENT_CLASS =
  "shrink-0 border-b border-white/10 px-4 py-0.5"

/** Meta / stats block directly under the engagement row in detail popups. */
export const DETAIL_MODAL_COLLAPSIBLE_META_CLASS =
  "border-b border-white/10 px-4 py-1 text-sm"

/** Main feed card: like / comment / share / vault under media. */
export const FEED_CARD_ENGAGEMENT_ROW_CLASS =
  "border-t border-white/10 px-4 py-1"

/** @deprecated Use DETAIL_MODAL_MEDIA_ACTIONS_WRAP_CLASS */
export const DETAIL_MODAL_MEDIA_ACTIONS_CLASS =
  DETAIL_MODAL_MEDIA_ACTIONS_WRAP_CLASS

/** Right-column engagement when media lives in the left column (mobile comment focus hides media stack). */
export function detailModalEngagementInPanel(
  hasMedia: boolean,
  commentsFocused: boolean,
  isMobile: boolean
): boolean {
  if (!hasMedia) return true
  return commentsFocused && isMobile
}
