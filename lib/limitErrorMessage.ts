type ErrorLike = {
  message?: string | null
  details?: string | null
  hint?: string | null
}

function normalizeErrorText(error: unknown): string {
  if (!error) return ""
  if (typeof error === "string") return error.toLowerCase()
  const e = error as ErrorLike
  return `${e.message ?? ""} ${e.details ?? ""} ${e.hint ?? ""}`.toLowerCase()
}

export function handleLimitError(error: unknown): string | null {
  const text = normalizeErrorText(error)
  if (!text) return null

  if (text.includes("3 trades")) {
    return "Free plan allows 3 trades per day. Upgrade to Pro."
  }
  if (text.includes("1 public trade")) {
    return "Only 1 public trade per day on free plan."
  }
  if (text.includes("1 post")) {
    return "Free plan allows 1 post per day."
  }
  if (text.includes("10 messages")) {
    return "You've reached your daily messaging limit."
  }

  return null
}
