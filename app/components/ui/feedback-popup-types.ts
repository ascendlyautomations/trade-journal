export type FeedbackPopupType = "success" | "error" | "warning" | "info"

export type FeedbackPopupInput = {
  message: string
  type?: FeedbackPopupType
  title?: string
  /** When true, modal stays open until the user dismisses it. */
  persist?: boolean
}
