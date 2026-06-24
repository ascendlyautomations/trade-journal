export function handleSupabaseError(error: unknown): string {
  const e = error as { message?: string } | null | undefined
  if (!e?.message) return "Something went wrong"

  const msg = String(e.message).toLowerCase()

  if (msg.includes("account") && msg.includes("limit")) {
    return "Free plan allows up to 3 accounts. Upgrade to Pro for unlimited accounts."
  }

  if (msg.includes("not deleted") || msg.includes("delete policy")) {
    return String(e.message)
  }

  return "Something went wrong. Please try again."
}
