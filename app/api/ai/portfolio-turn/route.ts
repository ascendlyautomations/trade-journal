import { NextResponse } from "next/server"
import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  consumeDurableUserRateLimit,
  rateLimitExceededResponse,
} from "@/lib/server/durableUserRateLimit"
import { requireAIFeatureEntitlement } from "@/lib/server/requireAIFeatureEntitlement"
import { analyzeTradeFailureFromError } from "@/lib/server/openAiRouteSupport"
import { buildPortfolioAnalysisContext } from "@/lib/server/ai/aiPortfolioContextBuilder"
import { runTradeAiCompletion } from "@/lib/server/ai/aiOpenAiTurn"
import {
  appendTurnIdempotent,
  createPortfolioConversation,
  logAiUsage,
} from "@/lib/server/ai/aiConversationService"
import type { AiPortfolioScope } from "@/lib/server/ai/aiConversationTypes"
import { parseAttachments } from "@/lib/server/ai/aiMessageAttachments"
import {
  buildAttachedTradesPromptSection,
  enrichPriorUserTurnContent,
  resolveOpenAiImageUrls,
  tradeIdsFromAttachments,
} from "@/lib/server/ai/aiCoachAttachmentResolver"
import {
  PORTFOLIO_TURN_SYSTEM_PROMPT,
  buildPortfolioTurnPrimaryPrompt,
} from "@/lib/generalTradeCoachPrompt"

export const runtime = "nodejs"
export const maxDuration = 60

export async function POST(req: Request) {
  const { user } = await getRouteUserAuth(req)
  if (!user) {
    return NextResponse.json(
      { error: "Unauthorized", reply: "Sign in to use Trade AI.", code: "unauthorized" },
      { status: 401 }
    )
  }

  const entitlement = await requireAIFeatureEntitlement(user.id, {
    reply: "AI Analyst is a Pro feature.",
  })
  if (!entitlement.ok) {
    return entitlement.response
  }

  let body: {
    conversationId?: string | null
    createConversation?: boolean
    title?: string
    scope?: AiPortfolioScope
    userMessage?: {
      id?: string
      displayContent?: string
      openaiContent?: string
      createdAt?: string | null
      attachments?: unknown
    }
    assistantMessageId?: string
    messages?: Array<{ role?: string; content?: string; attachments?: unknown }>
  }

  try {
    body = await req.json()
  } catch {
    return NextResponse.json({ error: "Invalid JSON", code: "invalid_json" }, { status: 400 })
  }

  const userMsg = body.userMessage
  if (!userMsg?.id || !userMsg.displayContent?.trim()) {
    return NextResponse.json({ error: "Missing user message", code: "invalid_request" }, { status: 400 })
  }

  let conversationId = body.conversationId?.trim() ?? ""
  let scope: AiPortfolioScope = body.scope ?? { preset: "all_time", accountIds: "all" }

  if (!conversationId && body.createConversation !== false) {
    const created = await createPortfolioConversation(
      supabaseServiceRole,
      user.id,
      body.title?.trim() || "General Trade AI",
      scope
    )
    if (created.error || !created.conversationId) {
      return NextResponse.json(
        { error: created.error ?? "conversation_create_failed" },
        { status: 500 }
      )
    }
    conversationId = created.conversationId
  }

  if (!conversationId) {
    return NextResponse.json({ error: "Missing conversationId", code: "invalid_request" }, { status: 400 })
  }

  const { data: convRow } = await supabaseServiceRole
    .from("ai_coach_conversations")
    .select("id, kind, scope")
    .eq("id", conversationId)
    .eq("user_id", user.id)
    .maybeSingle()

  if (!convRow) {
    return NextResponse.json({ error: "Conversation not found", code: "not_found" }, { status: 404 })
  }

  if (!body.scope && convRow.scope && typeof convRow.scope === "object") {
    scope = convRow.scope as AiPortfolioScope
  }

  const rate = await consumeDurableUserRateLimit(user.id, "ai_analyze_trade")
  if (!rate.allowed) {
    return rateLimitExceededResponse(rate.retryAfterSec)
  }

  const portfolio = await buildPortfolioAnalysisContext(
    supabaseServiceRole,
    user.id,
    scope
  )

  const userAttachments = parseAttachments(userMsg.attachments)
  const attachedTradeIds = tradeIdsFromAttachments(userAttachments)
  const attachedTradesBlock =
    attachedTradeIds.length > 0
      ? await buildAttachedTradesPromptSection(
          supabaseServiceRole,
          user.id,
          attachedTradeIds
        )
      : ""

  const priorTurnCount = (body.messages ?? []).filter(
    (m) => m && (m.role === "user" || m.role === "assistant")
  ).length

  const userQuestion =
    userMsg.openaiContent?.trim() || userMsg.displayContent.trim()

  const primaryPrompt = buildPortfolioTurnPrimaryPrompt({
    scopeLabel: portfolio.scopeLabel,
    statisticsBlock: portfolio.statisticsBlock,
    tradesCsvBlock: portfolio.tradesCsvBlock,
    limitations: portfolio.limitations,
    attachedTradesBlock: attachedTradesBlock || undefined,
    userQuestion,
    hasPriorTurns: priorTurnCount > 0,
  })

  const attachmentUrls = await resolveOpenAiImageUrls(
    supabaseServiceRole,
    user.id,
    userAttachments
  )
  const primaryImages = attachmentUrls.map((url) => ({
    kind: "image_url" as const,
    url,
  }))

  const priorMessages = await Promise.all(
    (body.messages ?? [])
      .filter(
        (m): m is { role: string; content: string; attachments?: unknown } =>
          !!m &&
          typeof m.role === "string" &&
          typeof m.content === "string" &&
          (m.role === "user" || m.role === "assistant")
      )
      .map(async (m) => {
        const attachments = parseAttachments(m.attachments)
        const urls =
          m.role === "user"
            ? await resolveOpenAiImageUrls(
                supabaseServiceRole,
                user.id,
                attachments
              )
            : []
        const content =
          m.role === "user"
            ? await enrichPriorUserTurnContent(
                supabaseServiceRole,
                user.id,
                m.content,
                attachments
              )
            : m.content
        return {
          role: m.role as "user" | "assistant",
          content,
          imageUrls: urls,
        }
      })
  )

  try {
    const completion = await runTradeAiCompletion({
      systemPrompt: PORTFOLIO_TURN_SYSTEM_PROMPT,
      primaryUserPrompt: primaryPrompt,
      primaryImages,
      priorMessages,
    })

    const assistantId = body.assistantMessageId?.trim() || crypto.randomUUID()

    const persisted = await appendTurnIdempotent(
      supabaseServiceRole,
      user.id,
      conversationId,
      {
        id: userMsg.id,
        displayContent: userMsg.displayContent.trim(),
        openaiContent: userMsg.openaiContent?.trim() || userMsg.displayContent.trim(),
        attachments: userAttachments,
        createdAt: userMsg.createdAt ?? null,
      },
      {
        id: assistantId,
        content: completion.reply,
        createdAt: new Date().toISOString(),
      }
    )

    if (persisted.error) {
      return NextResponse.json(
        {
          reply: completion.reply,
          conversationId,
          persistError: persisted.error,
          code: "persist_failed",
          shouldPersist: false,
        },
        { status: 200 }
      )
    }

    await logAiUsage(supabaseServiceRole, {
      userId: user.id,
      conversationId,
      route: "ai/portfolio-turn",
      model: completion.usage.model,
      promptTokens: completion.usage.promptTokens,
      completionTokens: completion.usage.completionTokens,
      totalTokens: completion.usage.totalTokens,
    })

    return NextResponse.json({
      reply: completion.reply,
      conversationId,
      assistantMessageId: assistantId,
      persisted: persisted.result,
      shouldPersist: true,
    })
  } catch (error) {
    const failure = analyzeTradeFailureFromError(error)
    return NextResponse.json(
      { error: failure.error, reply: failure.reply, code: failure.code },
      { status: failure.status }
    )
  }
}