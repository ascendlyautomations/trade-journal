import { SHOWCASE_USER_ID } from "./guestShowcaseAccount"

export type GuestSessionIssuance = {
  userId: string
  accessToken: string
  refreshToken: string
  expiresAt: number | null
  sessionId: string
}

type GuestSessionIssueError = "unavailable" | "invalid_response"

/** Mint a read-only guest session for the production showcase account (Explore as Guest). */
export async function issueGuestSession(): Promise<
  GuestSessionIssuance | GuestSessionIssueError
> {
  let response: Response
  try {
    response = await fetch("/api/guest-explore/session", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{}",
    })
  } catch {
    return "unavailable"
  }

  if (!response.ok) return "unavailable"

  let body: unknown
  try {
    body = await response.json()
  } catch {
    return "invalid_response"
  }

  if (!body || typeof body !== "object") return "invalid_response"
  const row = body as Record<string, unknown>
  const accessToken = row.access_token
  const refreshToken = row.refresh_token
  const sessionId = row.session_id
  const userId = row.user_id
  if (typeof accessToken !== "string" || !accessToken.trim()) {
    return "invalid_response"
  }
  if (typeof refreshToken !== "string" || !refreshToken.trim()) {
    return "invalid_response"
  }
  if (typeof sessionId !== "string" || !sessionId.trim()) {
    return "invalid_response"
  }
  if (typeof userId !== "string" || !userId.trim()) {
    return "invalid_response"
  }
  if (userId.trim().toLowerCase() !== SHOWCASE_USER_ID) {
    return "invalid_response"
  }

  const expiresAt =
    typeof row.expires_at === "number" && Number.isFinite(row.expires_at)
      ? row.expires_at
      : null

  return {
    userId: userId.trim().toLowerCase(),
    accessToken: accessToken.trim(),
    refreshToken: refreshToken.trim(),
    expiresAt,
    sessionId: sessionId.trim(),
  }
}

export async function finalizeGuestSession(accessToken: string): Promise<boolean> {
  try {
    const response = await fetch("/api/guest-explore/finalize", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: "{}",
    })
    return response.status === 204
  } catch {
    return false
  }
}
