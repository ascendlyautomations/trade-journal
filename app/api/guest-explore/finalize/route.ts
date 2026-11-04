import { NextResponse } from "next/server"
import {
  decodeJwtPayload,
  releaseShowcaseGuestSession,
} from "@/lib/guestSessionServer"
import { isShowcaseUserId } from "@/lib/guestShowcaseAccount"

export const runtime = "nodejs"

/** After browser setSession — release GoTrue row so the JWT is guest read-only. */
export async function POST(request: Request) {
  const auth = request.headers.get("authorization") ?? ""
  const match = auth.match(/^Bearer\s+(.+)$/i)
  const accessToken = match?.[1]?.trim()
  if (!accessToken) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 })
  }

  const claims = decodeJwtPayload(accessToken)
  const sub = claims?.sub
  if (typeof sub !== "string" || !isShowcaseUserId(sub)) {
    return NextResponse.json({ error: "forbidden" }, { status: 403 })
  }

  const sessionId = claims?.session_id
  if (typeof sessionId !== "string" || !sessionId) {
    return NextResponse.json({ error: "invalid_session" }, { status: 400 })
  }

  const released = await releaseShowcaseGuestSession(sessionId)
  if (!released) {
    return NextResponse.json({ error: "release_failed" }, { status: 503 })
  }

  return new NextResponse(null, { status: 204 })
}
