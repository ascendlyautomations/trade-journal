/**
 * Platform presentation layer.
 *
 * Separates *presentation* for Capacitor iOS vs web while keeping shared
 * pages, hooks, auth, and Supabase. Native and web branches currently render
 * the existing UI identically — future native redesigns change only the
 * `native/` implementations.
 */
export { default as PlatformChrome } from "./PlatformChrome"
export { default as PlatformNavbar } from "./PlatformNavbar"
export { default as PlatformBottomNavigation } from "./PlatformBottomNavigation"
export {
  default as PlatformFeedHeader,
  PlatformFeedModeToggle,
} from "./PlatformFeedHeader"
export {
  default as PlatformCalendarHeader,
  PlatformCalendarFilters,
} from "./PlatformCalendarHeader"
export { default as PlatformDashboardCalendarButton } from "./PlatformDashboardCalendarButton"
export { default as PlatformDashboardTradesButton } from "./PlatformDashboardTradesButton"
export { default as PlatformTradesHeader } from "./PlatformTradesHeader"
export {
  default as PlatformMessagesHeader,
  PlatformMessagesWebInboxActions,
} from "./PlatformMessagesHeader"
export { default as PlatformPageHeader } from "./PlatformPageHeader"
export { NATIVE_IOS_PAGE_HEADER_ACTION_CLASS } from "./PlatformPageHeader"
export { default as PlatformProfileHeader } from "./PlatformProfileHeader"
export { default as PlatformProfileTradesToolbar } from "./PlatformProfileTradesToolbar"
export type { ProfileTradesOutcomeFilter } from "./PlatformProfileTradesToolbar"
export { default as PlatformSearch } from "./PlatformSearch"
export { default as PlatformNotifications } from "./PlatformNotifications"
export { default as PlatformSheet } from "./PlatformSheet"
export { default as PlatformModal } from "./PlatformModal"
export { default as PlatformDialog } from "./PlatformDialog"
export { default as PlatformBackButton } from "./PlatformBackButton"
export { default as PlatformCreateFlow } from "./PlatformCreateFlow"
export { default as PlatformSettingsEntry } from "./PlatformSettingsEntry"
export { usePlatformPresentation } from "./usePlatformPresentation"
