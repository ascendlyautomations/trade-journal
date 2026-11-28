import { NextResponse } from "next/server"
import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadConversationMessages } from "@/lib/server/ai/aiConversationService"
import type { AiMessageAttachment } from "@/lib/server/ai/aiConversationTypes"
import { signedUrlsForAttachments } from "@/lib/server/ai/aiAttachmentStorage"
import { publicImageUrlFromStoragePath } from "@/lib/server/ai/aiOpenAiTurn"

export const runtime = "nodejs"

export async function GET(
  req: Request,
  ctx: { params: Promise<{ id: string }> }
) {
  const { user } = await getRouteUserAuth(req)
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { id } = await ctx.params
  const conversationId = id?.trim()
  if (!conversationId) {
    return NextResponse.json({ error: "Missing id" }, { status: 400 })
  }

  const { data: conv } = await supabaseServiceRole
    .from("ai_coach_conversations")
    .select("id, kind, trade_id, title, scope")
    .eq("id", conversationId)
    .eq("user_id", user.id)
    .maybeSingle()

  if (!conv) {
    return NextResponse.json({ error: "Not found" }, { status: 404 })
  }

  const messages = await loadConversationMessages(
    supabaseServiceRole,
    user.id,
    conversationId
  )

  const mappedMessages = await Promise.all(
    messages.map(async (m) => {
      const raw = (Array.isArray(m.attachments) ? m.attachments : []) as AiMessageAttachment[]
      const coachUrls = await signedUrlsForAttachments(supabaseServiceRole, raw)
      let coachIndex = 0
      const attachments = raw.map((item) => {
        if (item.kind === "trade") {
          return {
            kind: "trade",
            tradeId: item.tradeId ?? null,
            storagePath: null,
            url: "",
          }
        }
        if (item.kind === "screenshot" && item.storagePath) {
          return {
            kind: item.kind,
            tradeId: item.tradeId ?? null,
            storagePath: item.storagePath,
            url: publicImageUrlFromStoragePath(item.storagePath) ?? item.url ?? "",
          }
        }
        const url = coachUrls[coachIndex] ?? item.url ?? ""
        if (item.kind === "uploaded_image") coachIndex += 1
        return {
          kind: item.kind ?? "uploaded_image",
          tradeId: item.tradeId ?? null,
          storagePath: item.storagePath ?? null,
          url,
        }
      })
      return {
        id: m.id,
        role: m.role,
        content:
          m.role === "user" && m.displayContent
            ? m.displayContent
            : m.content,
        promptKey: m.promptKey,
        attachments,
        createdAt: m.createdAt,
      }
    })
  )

  const scope =
    conv.scope && typeof conv.scope === "object" && !Array.isArray(conv.scope)
      ? (conv.scope as Record<string, unknown>)
      : null
  const factsSnapshot =
    conv.kind === "psychology" && scope?.factsSnapshot != null
      ? scope.factsSnapshot
      : null

  return NextResponse.json({
    conversation: {
      ...conv,
      factsSnapshot,
    },
    messages: mappedMessages,
  })
}