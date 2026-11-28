import { NextResponse } from "next/server"
import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  consumeDurableUserRateLimit,
  rateLimitExceededResponse,
} from "@/lib/server/durableUserRateLimit"
import { requireAIFeatureEntitlement } from "@/lib/server/requireAIFeatureEntitlement"
import { analyzeTradeFailureFromError } from "@/lib/server/openAiRouteSupport"
import { buildAuthoritativeTradeContext } from "@/lib/server/ai/aiTradeContextBuilder"
import { buildAuthoritativeTradeAnalysisPrompt } from "@/lib/server/ai/buildTradeAnalysisUserPrompt"
import {
  TRADE_AI_TURN_SYSTEM_PROMPT,
  buildTradeTurnUserDirective,
} from "@/lib/tradeAiCoachPrompt"
import { runTradeAiCompletion, publicImageUrlFromStoragePath } from "@/lib/server/ai/aiOpenAiTurn"
import {
  appendTurnIdempotent,
  loadTradeConversationId,
  logAiUsage,
  openTradeConversation,
} from "@/lib/server/ai/aiConversationService"
import type { AiTurnUserMessageInput } from "@/lib/server/ai/aiConversationTypes"
import { parseAttachments } from "@/lib/server/ai/aiMessageAttachments"
import { resolveOpenAiImageUrls } from "@/lib/server/ai/aiCoachAttachmentResolver"

export const runtime = "nodejs"
export const maxDuration = 60

type TradeTurnBody = {
  tradeId?: string
  conversationId?: string | null
  userMessage?: {
    id?: string
    displayContent?: string
    openaiContent?: string
    promptKey?: string | null
    createdAt?: string | null
    attachments?: unknown[]
  }
  assistantMessageId?: string
  messages?: Array<{ role?: string; content?: string; attachments?: unknown }>
  persistOnly?: boolean
}

export async function POST(req: Request) {
  const { user, authError } = await getRouteUserAuth(req)
  if (!user) {
    return NextResponse.json(
      {
        error: "Unauthorized",
        reply: "Sign in to use Trade AI.",
        code: "unauthorized",
      },
      { status: 401 }
    )
  }

  let body: TradeTurnBody
  try {
    body = (await req.json()) as TradeTurnBody
  } catch {
    return NextResponse.json(
      { error: "Invalid JSON", code: "invalid_json" },
      { status: 400 }
    )
  }

  const tradeId = body.tradeId?.trim()
  const userMsg = body.userMessage
  const userMessageId = userMsg?.id?.trim()
  const assistantMessageId = body.assistantMessageId?.trim()

  if (!tradeId || !userMessageId || !userMsg?.displayContent?.trim()) {
    return NextResponse.json(
      {
        error: "Missing trade or user message",
        code: "invalid_request",
      },
      { status: 400 }
    )
  }

  const entitlement = await requireAIFeatureEntitlement(user.id, {
    reply: "AI Analyst is a Pro feature.",
  })
  if (!entitlement.ok) {
    return entitlement.response
  }

  let conversationId =
    body.conversationId?.trim() ||
    (await loadTradeConversationId(supabaseServiceRole, user.id, tradeId)) ||
    ""

  if (!conversationId) {
    const opened = await openTradeConversation(supabaseServiceRole, user.id, tradeId)
    if (opened.error || !opened.conversationId) {
      return NextResponse.json(
        { error: opened.error ?? "conversation_open_failed", code: "persist_failed" },
        { status: 500 }
      )
    }
    conversationId = opened.conversationId
  }

  const rate = await consumeDurableUserRateLimit(user.id, "ai_analyze_trade")
  if (!rate.allowed) {
    return rateLimitExceededResponse(rate.retryAfterSec)
  }

  const context = await buildAuthoritativeTradeContext(
    supabaseServiceRole,
    user.id,
    tradeId
  )
  if (!context) {
    return NextResponse.json(
      {
        error: "Trade not found",
        reply: "We couldn't find that trade. Refresh and try again.",
        code: "trade_not_found",
      },
      { status: 404 }
    )
  }

  const userAttachments = parseAttachments(userMsg.attachments)
  const uploadUrls = await resolveOpenAiImageUrls(
    supabaseServiceRole,
    user.id,
    userAttachments
  )

  const imageUrl = publicImageUrlFromStoragePath(context.imagePath)
  const primaryImageUrls = [
    ...(imageUrl ? [imageUrl] : []),
    ...uploadUrls,
  ]
  const primaryImages = primaryImageUrls.map((url) => ({
    kind: "image_url" as const,
    url,
  }))

  const userDirective = buildTradeTurnUserDirective({
    promptKey: userMsg.promptKey,
    displayContent: userMsg.displayContent.trim(),
    openaiContent: userMsg.openaiContent,
  })

  const primaryPrompt = `${buildAuthoritativeTradeAnalysisPrompt(context, {
    hasScreenshot: Boolean(imageUrl) || uploadUrls.length > 0,
    deferOutputFormat: true,
  })}

${userDirective}`

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
        return {
          role: m.role as "user" | "assistant",
          content: m.content,
          imageUrls: urls,
        }
      })
  )

  const persistAttachments = [...userAttachments]
  if (context.imagePath) {
    persistAttachments.unshift({
      kind: "screenshot",
      url: imageUrl ?? "",
      storagePath: context.imagePath,
      tradeId,
    })
  }

  try {
    const completion = await runTradeAiCompletion({
      systemPrompt: TRADE_AI_TURN_SYSTEM_PROMPT,
      primaryUserPrompt: primaryPrompt,
      primaryImages,
      priorMessages,
    })

    const assistantId =
      assistantMessageId ||
      crypto.randomUUID()

    const userTurn: AiTurnUserMessageInput = {
      id: userMessageId,
      displayContent: userMsg.displayContent.trim(),
      openaiContent: userMsg.openaiContent?.trim() || userMsg.displayContent.trim(),
      promptKey: userMsg.promptKey ?? null,
      attachments: persistAttachments,
      createdAt: userMsg.createdAt ?? null,
    }

    const persisted = await appendTurnIdempotent(
      supabaseServiceRole,
      user.id,
      conversationId,
      userTurn,
      {
        id: assistantId,
        content: completion.reply,
        createdAt: new Date().toISOString(),
      }
    )

    if (persisted.error) {
      console.error("[ai/trade-turn] persist failed", persisted.error)
      return NextResponse.json(
        {
          reply: completion.reply,
          result: completion.reply,
          conversationId,
          assistantMessageId: assistantId,
          userMessageId,
          persistError: persisted.error,
          code: "persist_failed",
          shouldPersist: false,
        },
        { status: 200 }
      )
    }

    await supabaseServiceRole
      .from("trades")
      .update({ ai_feedback: completion.reply })
      .eq("id", tradeId)
      .eq("user_id", user.id)

    await logAiUsage(supabaseServiceRole, {
      userId: user.id,
      conversationId,
      route: "ai/trade-turn",
      model: completion.usage.model,
      promptTokens: completion.usage.promptTokens,
      completionTokens: completion.usage.completionTokens,
      totalTokens: completion.usage.totalTokens,
    })

    return NextResponse.json({
      reply: completion.reply,
      result: completion.reply,
      conversationId,
      assistantMessageId: assistantId,
      userMessageId,
      persisted: persisted.result,
      shouldPersist: true,
    })
  } catch (error) {
    const failure = analyzeTradeFailureFromError(error)
    console.error("[ai/trade-turn] Analysis error", {
      code: failure.code,
      tradeId,
      userId: user.id,
    })
    return NextResponse.json(
      {
        error: failure.error,
        reply: failure.reply,
        code: failure.code,
        conversationId,
      },
      { status: failure.status }
    )
  }
}