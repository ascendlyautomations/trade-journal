import { NextResponse } from "next/server"
import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { listConversationInbox } from "@/lib/server/ai/aiConversationService"

export const runtime = "nodejs"

export async function GET(req: Request) {
  const { user } = await getRouteUserAuth(req)
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const limitRaw = new URL(req.url).searchParams.get("limit")
  const limit = Math.min(200, Math.max(1, Number(limitRaw) || 50))

  const { rows, error } = await listConversationInbox(
    supabaseServiceRole,
    user.id,
    limit
  )

  if (error) {
    return NextResponse.json({ error }, { status: 500 })
  }

  return NextResponse.json({ conversations: rows })
}