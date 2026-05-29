export type FeedbackPopupType = "success" | "error" | "warning" | "info"

export type FeedbackPopupInput = {
  message: string
  type?: FeedbackPopupType
}
