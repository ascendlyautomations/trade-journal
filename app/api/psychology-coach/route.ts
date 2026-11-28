import { NextResponse } from "next/server"
import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { openAiApiKey } from "@/lib/server/openAiRouteSupport"
import {
  buildPsychologyCoachOpenAiMessages,
  splitPsychologyCoachOpenAiTurn,
  type PsychologyCoachFactsPayload,
} from "@/lib/psychologyCoachPrompt"
import { runTradeAiCompletion } from "@/lib/server/ai/aiOpenAiTurn"
import { openAiErrorMetaForLog } from "@/lib/server/openAiRouteSupport"
import { normalizeAIProseResponse } from "@/lib/normalizeAIGeneratedText"
import {
  consumeDurableUserRateLimit,
  rateLimitExceededResponse,
} from "@/lib/server/durableUserRateLimit"
import { requireAIFeatureEntitlement } from "@/lib/server/requireAIFeatureEntitlement"
import type { Json } from "@/lib/database.types"
import { mapOpenAiErrorToHttp, openAiCoachModel } from "@/lib/server/openAiChatCompletion"
import {
  appendAssistantMessageIdempotent,
  appendTurnIdempotent,
  createPsychologyConversation,
  logAiUsage,
} from "@/lib/server/ai/aiConversationService"

export const runtime = "nodejs"
export const maxDuration = 60

export async function POST(req: Request) {
  const { user } = await getRouteUserAuth(req)

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  if (!openAiApiKey()) {
    return NextResponse.json(
      { error: "AI service unavailable" },
      { status: 503 }
    )
  }

  const rate = await consumeDurableUserRateLimit(user.id, "ai_psychology_coach")
  if (!rate.allowed) {
    return rateLimitExceededResponse(rate.retryAfterSec)
  }

  const entitlement = await requireAIFeatureEntitlement(user.id, {
    reply:
      "Psychology Coach AI is a TraxPro feature. Upgrade your plan on the web to unlock it.",
  })
  if (!entitlement.ok) {
    return entitlement.response
  }

  const traceId = crypto.randomUUID().slice(0, 8)
  let tracePhase = "start"

  try {
    const body = await req.json()
    const facts = body?.facts as PsychologyCoachFactsPayload | undefined
    const mode = typeof body?.mode === "string" ? body.mode : "explain"
    const messages = Array.isArray(body?.messages) ? body.messages : []

    if (!facts || typeof facts !== "object") {
      return NextResponse.json({ error: "Missing psychology facts" }, { status: 400 })
    }

    if (body?.userId && body.userId !== user.id) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 })
    }

    const openAiMode = mode === "followUp" ? "followUp" : "explain"
    const cachedReply =
      typeof body?.cachedReply === "string" ? body.cachedReply.trim() : ""
    const persistCachedOnly =
      body?.persistCachedOnly === true &&
      openAiMode === "explain" &&
      cachedReply.length > 0

    let conversationId =
      typeof body?.conversationId === "string" ? body.conversationId.trim() : ""

    if (
      !conversationId &&
      openAiMode === "explain" &&
      body?.createConversation !== false
    ) {
      tracePhase = "create_conversation"
      const scope = facts.scope ?? {}
      const created = await createPsychologyConversation(supabaseServiceRole, user.id, {
        title: `Psychology Coach · ${scope.label ?? "Analytics"}`,
        scopeLabel: String(scope.label ?? "Analytics"),
        scopeFingerprint: String(scope.fingerprint ?? facts.factsHash ?? ""),
        factsHash: String(facts.factsHash ?? ""),
        scope: {
          label: scope.label,
          fingerprint: scope.fingerprint,
          factsHash: facts.factsHash,
        },
        factsSnapshot: facts as unknown as Record<string, unknown>,
      })
      if (created.conversationId) {
        conversationId = created.conversationId
      } else if (created.error) {
        console.warn("[PsychologyCoachTrace] conversation.create_failed", {
          traceId,
          code: created.error.slice(0, 80),
        })
      }
    }

    const assistantMessageId =
      typeof body?.assistantMessageId === "string"
        ? body.assistantMessageId.trim()
        : crypto.randomUUID()

    if (persistCachedOnly) {
      tracePhase = "persist_cached"
      let persistError: string | undefined
      if (conversationId) {
        const persisted = await appendAssistantMessageIdempotent(
          supabaseServiceRole,
          user.id,
          conversationId,
          {
            id: assistantMessageId,
            content: cachedReply,
            promptKey: "psychology_explain",
            createdAt: new Date().toISOString(),
          }
        )
        persistError = persisted.error
      }
      console.info("[PsychologyCoachTrace] request.done", {
        traceId,
        phase: tracePhase,
        status: 200,
        replyLen: cachedReply.length,
        hasConversation: Boolean(conversationId),
        persistCachedOnly: true,
      })
      return NextResponse.json({
        reply: cachedReply,
        usage: null,
        conversationId: conversationId || null,
        assistantMessageId,
        persistError: persistError ?? null,
        persistedCached: true,
      })
    }

    tracePhase = "openai"
    const openAiMessages = buildPsychologyCoachOpenAiMessages(facts, openAiMode, messages)
    const turn = splitPsychologyCoachOpenAiTurn(openAiMessages)

    console.info("[PsychologyCoachTrace] openai.request", {
      traceId,
      phase: tracePhase,
      model: openAiCoachModel(),
      mode: openAiMode,
      anchorUserChars: turn.primaryUserPrompt.length,
      priorTurns: turn.priorMessages.length,
    })

    const completion = await runTradeAiCompletion({
      systemPrompt: turn.systemPrompt,
      primaryUserPrompt: turn.primaryUserPrompt,
      priorMessages: turn.priorMessages,
    })

    const reply = completion.reply
    if (!reply) {
      return NextResponse.json({ error: "No response generated" }, { status: 500 })
    }

    tracePhase = "log_usage"
    try {
      await logAiUsage(supabaseServiceRole, {
        userId: user.id,
        conversationId: conversationId || null,
        route: "psychology-coach",
        model: openAiCoachModel(),
        promptTokens: completion.usage.promptTokens,
        completionTokens: completion.usage.completionTokens,
        totalTokens: completion.usage.totalTokens,
      })
    } catch (usageError) {
      console.warn("[PsychologyCoachTrace] usage.log_failed", {
        traceId,
        message: usageError instanceof Error ? usageError.message.slice(0, 120) : "unknown",
      })
    }

    let persistError: string | undefined
    if (conversationId) {
      const userMsg = body?.userMessage as
        | {
            id?: string
            displayContent?: string
            createdAt?: string
          }
        | undefined

      if (openAiMode === "followUp" && userMsg?.id && userMsg.displayContent?.trim()) {
        const persisted = await appendTurnIdempotent(
          supabaseServiceRole,
          user.id,
          conversationId,
          {
            id: userMsg.id,
            displayContent: userMsg.displayContent.trim(),
            openaiContent: userMsg.displayContent.trim(),
            promptKey: "psychology_follow_up",
            createdAt: userMsg.createdAt ?? null,
          },
          {
            id: assistantMessageId,
            content: reply,
            createdAt: new Date().toISOString(),
          }
        )
        persistError = persisted.error
      } else {
        const persisted = await appendAssistantMessageIdempotent(
          supabaseServiceRole,
          user.id,
          conversationId,
          {
            id: assistantMessageId,
            content: reply,
            promptKey:
              openAiMode === "followUp"
                ? "psychology_follow_up"
                : "psychology_explain",
            createdAt: new Date().toISOString(),
          }
        )
        persistError = persisted.error
      }
    }

    const factsHash = typeof facts.factsHash === "string" ? facts.factsHash : null
    if (factsHash && mode === "summary") {
      await supabaseServiceRole.from("psychology_coach_snapshots").upsert(
        {
          user_id: user.id,
          facts_hash: factsHash,
          summary_json: facts as unknown as Json,
          ai_explanation: reply,
          generated_at: new Date().toISOString(),
        },
        { onConflict: "user_id" }
      )
    }

    console.info("[PsychologyCoachTrace] request.done", {
      traceId,
      phase: tracePhase,
      status: 200,
      replyLen: reply.length,
      hasConversation: Boolean(conversationId),
      persistCachedOnly: false,
      persistError: persistError ?? null,
    })
    return NextResponse.json({
      reply,
      usage: {
        prompt_tokens: completion.usage.promptTokens,
        completion_tokens: completion.usage.completionTokens,
        total_tokens: completion.usage.totalTokens,
      },
      conversationId: conversationId || null,
      assistantMessageId,
      persistError: persistError ?? null,
    })
  } catch (error) {
    const mapped = mapOpenAiErrorToHttp(error)
    const openAiMeta = openAiErrorMetaForLog(error)
    const openAiDetail =
      error && typeof error === "object" && "message" in error
        ? String((error as { message?: string }).message ?? "").slice(0, 240)
        : ""
    console.warn("[PsychologyCoachTrace] request.error", {
      traceId,
      phase: tracePhase,
      status: mapped.status,
      code: mapped.body.code ?? null,
      openAi: openAiMeta,
      openAiDetail: openAiDetail || null,
    })
    if (mapped.status >= 500 || mapped.body.code) {
      console.error("[psychology-coach]", error)
    }
    return NextResponse.json(
      mapped.body.reply
        ? { error: mapped.body.error, reply: mapped.body.reply, code: mapped.body.code }
        : {
            error:
              mapped.body.error ??
              "Psychology coach unavailable. Your analytics still work offline.",
          },
      { status: mapped.status }
    )
  }
}