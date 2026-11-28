import { NextResponse } from "next/server"
import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { requireAIFeatureEntitlement } from "@/lib/server/requireAIFeatureEntitlement"
import { appendTurnIdempotent } from "@/lib/server/ai/aiConversationService"
import { parseAttachments } from "@/lib/server/ai/aiMessageAttachments"

export const runtime = "nodejs"

/**
 * Retry-save a completed turn without re-invoking OpenAI (idempotent on message ids).
 */
export async function POST(req: Request) {
  const { user } = await getRouteUserAuth(req)
  if (!user) {
    return NextResponse.json({ error: "Unauthorized", code: "unauthorized" }, { status: 401 })
  }

  const entitlement = await requireAIFeatureEntitlement(user.id)
  if (!entitlement.ok) {
    return entitlement.response
  }

  let body: {
    conversationId?: string
    userMessage?: {
      id?: string
      displayContent?: string
      openaiContent?: string
      promptKey?: string | null
      attachments?: unknown
      createdAt?: string | null
    }
    assistantMessage?: {
      id?: string
      content?: string
      createdAt?: string | null
    }
  }

  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: "Invalid JSON", code: "invalid_json" }, { status: 400 })
  }

  const conversationId = body.conversationId?.trim()
  const userMessage = body.userMessage
  const assistantMessage = body.assistantMessage

  if (
    !conversationId ||
    !userMessage?.id ||
    !userMessage.displayContent ||
    !assistantMessage?.id ||
    !assistantMessage.content
  ) {
    return NextResponse.json({ error: "Invalid request", code: "invalid_request" }, { status: 400 })
  }

  const { data: conv } = await supabaseServiceRole
    .from("ai_coach_conversations")
    .select("id")
    .eq("id", conversationId)
    .eq("user_id", user.id)
    .maybeSingle()

  if (!conv) {
    return NextResponse.json({ error: "Conversation not found", code: "not_found" }, { status: 404 })
  }

  const persisted = await appendTurnIdempotent(
    supabaseServiceRole,
    user.id,
    conversationId,
    {
      id: userMessage.id,
      displayContent: userMessage.displayContent,
      openaiContent: userMessage.openaiContent ?? userMessage.displayContent,
      promptKey: userMessage.promptKey ?? null,
      attachments: parseAttachments(userMessage.attachments),
      createdAt: userMessage.createdAt ?? null,
    },
    {
      id: assistantMessage.id,
      content: assistantMessage.content,
      createdAt: assistantMessage.createdAt ?? null,
    }
  )

  if (persisted.error || !persisted.result) {
    return NextResponse.json(
      {
        error: persisted.error ?? "persist_failed",
        code: "persist_failed",
      },
      { status: 500 }
    )
  }

  return NextResponse.json({ ok: true, persisted: persisted.result })
}