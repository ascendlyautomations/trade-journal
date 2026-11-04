import { NextResponse } from "next/server"
import { mintShowcaseGuestSession } from "@/lib/guestSessionServer"

export const runtime = "nodejs"

/** Web Explore as Guest — issue tokens before GoTrue session release (see finalize route). */
export async function POST() {
  const issued = await mintShowcaseGuestSession()
  if (!issued) {
    return NextResponse.json({ error: "unavailable" }, { status: 503 })
  }

  return NextResponse.json({
    access_token: issued.accessToken,
    refresh_token: issued.refreshToken,
    expires_at: issued.expiresAt,
    user_id: issued.userId,
    session_id: issued.sessionId,
  })
}
