import { NextResponse } from "next/server"
import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { updateConversationTitle } from "@/lib/server/ai/aiConversationService"

export const runtime = "nodejs"

type RouteContext = { params: Promise<{ id: string }> }

export async function PATCH(req: Request, context: RouteContext) {
  const { user } = await getRouteUserAuth(req)
  if (!user) {
    return NextResponse.json({ error: "Unauthorized", code: "unauthorized" }, { status: 401 })
  }

  const { id } = await context.params
  const conversationId = id?.trim()
  if (!conversationId) {
    return NextResponse.json({ error: "Missing conversation id", code: "invalid_request" }, { status: 400 })
  }

  let body: { title?: string }
  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: "Invalid JSON", code: "invalid_json" }, { status: 400 })
  }

  const title = typeof body.title === "string" ? body.title : ""
  const result = await updateConversationTitle(
    supabaseServiceRole,
    user.id,
    conversationId,
    title
  )

  if (!result.ok) {
    const status =
      result.code === "not_found"
        ? 404
        : result.code === "invalid_title"
          ? 400
          : 500
    return NextResponse.json(
      { error: result.error, code: result.code },
      { status }
    )
  }

  return NextResponse.json({ conversationId, title: title.trim() })
}