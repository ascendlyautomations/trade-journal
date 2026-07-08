export type FeedbackPopupType = "success" | "error" | "warning" | "info"

export type FeedbackPopupInput = {
  message: string
  type?: FeedbackPopupType
  title?: string
  /** When true, modal stays open until the user dismisses it. */
  persist?: boolean
  /** Primary dismiss button label (default "Close"). */
  dismissLabel?: string
  /** Runs after the popup closes (e.g. focus the invalid field). */
  onDismiss?: () => void
}
