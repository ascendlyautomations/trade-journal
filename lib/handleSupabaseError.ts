export function handleSupabaseError(error: unknown): string {
  const e = error as { message?: string } | null | undefined
  if (!e?.message) return "Something went wrong"

  const msg = String(e.message).toLowerCase()

  if (msg.includes("3 trades") || msg.includes("5 trades")) {
    return "Free plan limit reached. Upgrade to Pro for unlimited trades."
  }

  if (msg.includes("public trade")) {
    return "Upgrade to Pro to share more trades publicly."
  }

  if (msg.includes("1 post")) {
    return "Upgrade to Pro to post more content."
  }

  if (msg.includes("10 messages")) {
    return "Upgrade to Pro to send more messages."
  }

  if (msg.includes("not deleted") || msg.includes("delete policy")) {
    return String(e.message)
  }

  return "Something went wrong. Please try again."
}
