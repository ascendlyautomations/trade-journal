import { NextResponse } from "next/server"
import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { requireAIFeatureEntitlement } from "@/lib/server/requireAIFeatureEntitlement"
import { uploadAiCoachAttachment } from "@/lib/server/ai/aiAttachmentStorage"

export const runtime = "nodejs"

export async function POST(req: Request) {
  const { user } = await getRouteUserAuth(req)
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const entitlement = await requireAIFeatureEntitlement(user.id)
  if (!entitlement.ok) {
    return entitlement.response
  }

  const form = await req.formData()
  const file = form.get("file")
  const conversationId = String(form.get("conversationId") ?? "").trim() || null

  if (conversationId) {
    const { data: conv } = await supabaseServiceRole
      .from("ai_coach_conversations")
      .select("id")
      .eq("id", conversationId)
      .eq("user_id", user.id)
      .maybeSingle()
    if (!conv) {
      return NextResponse.json({ error: "Conversation not found" }, { status: 404 })
    }
  }

  if (!(file instanceof File)) {
    return NextResponse.json({ error: "Missing file" }, { status: 400 })
  }

  const bytes = Buffer.from(await file.arrayBuffer())
  const result = await uploadAiCoachAttachment(
    supabaseServiceRole,
    user.id,
    bytes,
    file.type || "image/jpeg",
    conversationId
  )

  if (result.error) {
    return NextResponse.json({ error: result.error }, { status: 400 })
  }

  return NextResponse.json({ attachment: result.attachment })
}