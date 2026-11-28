import { NextResponse } from "next/server"
import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  loadConversationMessages,
  loadTradeConversationId,
  openTradeConversation,
} from "@/lib/server/ai/aiConversationService"

export const runtime = "nodejs"

export async function GET(
  _req: Request,
  ctx: { params: Promise<{ tradeId: string }> }
) {
  const { user } = await getRouteUserAuth(_req)
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { tradeId } = await ctx.params
  if (!tradeId?.trim()) {
    return NextResponse.json({ error: "Missing tradeId" }, { status: 400 })
  }

  let conversationId = await loadTradeConversationId(
    supabaseServiceRole,
    user.id,
    tradeId
  )

  if (!conversationId) {
    const opened = await openTradeConversation(
      supabaseServiceRole,
      user.id,
      tradeId
    )
    conversationId = opened.conversationId || null
  }

  if (!conversationId) {
    return NextResponse.json({
      conversation: null,
      messages: [],
    })
  }

  const { data: conv } = await supabaseServiceRole
    .from("ai_coach_conversations")
    .select("id, kind, trade_id, title, scope")
    .eq("id", conversationId)
    .eq("user_id", user.id)
    .maybeSingle()

  const messages = await loadConversationMessages(
    supabaseServiceRole,
    user.id,
    conversationId
  )

  return NextResponse.json({
    conversation: conv,
    messages: messages.map((m) => ({
      id: m.id,
      role: m.role,
      content:
        m.role === "user" && m.displayContent ? m.displayContent : m.content,
      promptKey: m.promptKey,
      attachments: m.attachments,
      createdAt: m.createdAt,
    })),
  })
}