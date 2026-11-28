import { NextResponse } from "next/server"
import {
  ANALYZE_TRADE_SYSTEM_PROMPT,
  buildAnalyzeTradeHistoryContext,
  buildTradeAnalysisPrompt,
} from "@/lib/analyzeTradePrompt"
import { buildAuthoritativeTradeContext } from "@/lib/server/ai/aiTradeContextBuilder"
import { buildAuthoritativeTradeAnalysisPrompt } from "@/lib/server/ai/buildTradeAnalysisUserPrompt"
import { normalizeAIProseResponse } from "@/lib/normalizeAIGeneratedText"
import { tradeScreenshotPublicUrl } from "@/lib/storagePublicUrl"
import {
  consumeDurableUserRateLimit,
  rateLimitExceededResponse,
} from "@/lib/server/durableUserRateLimit"
import {
  analyzeTradeFailureFromError,
  getOpenAiClient,
  openAiAnalystModel,
  openAiApiKey,
  openAiErrorMetaForLog,
  openAiRetryDelayMs,
} from "@/lib/server/openAiRouteSupport"
import { requireAIFeatureEntitlement } from "@/lib/server/requireAIFeatureEntitlement"
import type { Database } from "@/lib/database.types"
import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

export const runtime = "nodejs"
export const maxDuration = 60

function resolveScreenshotPublicUrl(imagePath: string | null | undefined) {
  return tradeScreenshotPublicUrl(imagePath)
}

function isOpenAiImageFetchError(error: unknown): boolean {
  if (!error || typeof error !== "object") return false
  const e = error as {
    message?: string
    code?: string
    error?: { message?: string; code?: string }
  }
  const message = `${e.message ?? ""} ${e.error?.message ?? ""}`.toLowerCase()
  const code = `${e.code ?? ""} ${e.error?.code ?? ""}`.toLowerCase()
  return (
    code.includes("invalid_image_url") ||
    message.includes("invalid_image_url") ||
    message.includes("timeout while downloading") ||
    message.includes("error while downloading") ||
    message.includes("failed to download image") ||
    (message.includes("timeout") && message.includes("download"))
  )
}

function buildOpenAiMessages(
  prompt: string,
  imageUrl: string | null,
  priorMessages: Array<{ role: string; content: string }> = []
) {
  return [
    {
      role: "system" as const,
      content: ANALYZE_TRADE_SYSTEM_PROMPT,
    },
    {
      role: "user" as const,
      content: [
        {
          type: "text" as const,
          text: prompt,
        },
        ...(imageUrl
          ? [{ type: "image_url" as const, image_url: { url: imageUrl } }]
          : []),
      ],
    },
    ...priorMessages.map((message) => ({
      role: message.role as "user" | "assistant",
      content: message.content,
    })),
  ]
}

async function createTradeAnalysisCompletion(
  prompt: string,
  imageUrl: string | null,
  priorMessages: Array<{ role: string; content: string }> = []
) {
  const openai = getOpenAiClient()
  if (!openai) {
    throw Object.assign(new Error("OPENAI_API_KEY missing"), {
      code: "openai_not_configured",
    })
  }

  const run = (withImage: boolean) =>
    openai.chat.completions.create({
      model: openAiAnalystModel(),
      messages: buildOpenAiMessages(
        prompt,
        withImage ? imageUrl : null,
        priorMessages
      ),
    })

  if (!imageUrl) {
    return runWithTransientRetry(() => run(false))
  }

  try {
    return await runWithTransientRetry(() => run(true))
  } catch (error) {
    if (!isOpenAiImageFetchError(error)) {
      throw error
    }
    console.warn("[analyze-trade] Screenshot unavailable; trade-only analysis.", {
      openAi: openAiErrorMetaForLog(error),
    })
    return runWithTransientRetry(() => run(false))
  }
}

async function runWithTransientRetry<T>(operation: () => Promise<T>): Promise<T> {
  try {
    return await operation()
  } catch (error) {
    const delayMs = openAiRetryDelayMs(error)
    if (delayMs == null) throw error
    await new Promise((resolve) => setTimeout(resolve, delayMs))
    return operation()
  }
}

export async function POST(req: Request) {
  const { user, authError } = await getRouteUserAuth(req)

  if (!user) {
    console.warn("[analyze-trade] Unauthorized", {
      code: authError?.code,
      message: authError?.message,
    })
    return NextResponse.json(
      {
        error: "Unauthorized",
        reply: "Sign in to use Trade AI.",
        code: "unauthorized",
      },
      { status: 401 }
    )
  }

  if (!openAiApiKey()) {
    console.error("[analyze-trade] OPENAI_API_KEY is not configured")
    const failure = analyzeTradeFailureFromError(
      new Error("OPENAI_API_KEY missing")
    )
    return NextResponse.json(
      {
        error: failure.error,
        reply: failure.reply,
        code: failure.code,
      },
      { status: failure.status }
    )
  }

  let body: unknown
  try {
    body = await req.json()
  } catch {
    return NextResponse.json(
      {
        error: "Invalid JSON",
        reply: "Invalid request. Please try again.",
        code: "invalid_json",
      },
      { status: 400 }
    )
  }

  const trade = (body as { trade?: { id?: unknown } })?.trade
  const messages = (body as { messages?: unknown })?.messages
  const tradeId = trade?.id
  if (!tradeId) {
    return NextResponse.json(
      {
        error: "Missing trade id",
        reply: "Select a trade before running analysis.",
        code: "missing_trade_id",
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

  const { data: existingTrade, error: tradeLookupError } = await supabaseServiceRole
    .from("trades")
    .select("id, user_id, image_url")
    .eq("id", String(tradeId))
    .single()

  if (tradeLookupError) {
    console.error("[analyze-trade] Trade lookup failed", {
      tradeId: String(tradeId),
      userId: user.id,
      error: tradeLookupError,
    })
    return NextResponse.json(
      {
        error: "Trade not found",
        reply: "We couldn't find that trade. Refresh and try again.",
        code: "trade_not_found",
      },
      { status: 404 }
    )
  }

  if (!existingTrade || existingTrade.user_id !== user.id) {
    return NextResponse.json(
      {
        error: "Forbidden",
        reply: "You can only analyze your own trades.",
        code: "forbidden",
      },
      { status: 403 }
    )
  }

  const rate = await consumeDurableUserRateLimit(user.id, "ai_analyze_trade")
  if (!rate.allowed) {
    return rateLimitExceededResponse(rate.retryAfterSec)
  }

  try {
    const imageUrl = resolveScreenshotPublicUrl(existingTrade.image_url)

    const { data: historyRows, error: historyError } = await supabaseServiceRole
      .from("trades")
      .select(
        "id, ticker, pnl, rr, direction, session, strategy, created_at, duration_seconds, duration_text, entry_time, exit_time"
      )
      .eq("user_id", user.id)
      .order("created_at", { ascending: false })
      .limit(120)

    if (historyError) {
      console.error("[analyze-trade] History lookup failed", historyError)
    }

    const authoritative = await buildAuthoritativeTradeContext(
      supabaseServiceRole,
      user.id,
      String(tradeId)
    )

    const prompt = authoritative
      ? buildAuthoritativeTradeAnalysisPrompt(authoritative, {
          hasScreenshot: Boolean(imageUrl),
        })
      : buildTradeAnalysisPrompt(
          (body as { trade: Record<string, unknown> }).trade,
          buildAnalyzeTradeHistoryContext(
            historyRows ?? [],
            String(tradeId)
          ),
          { hasScreenshot: Boolean(imageUrl) }
        )
    const priorMessages = Array.isArray(messages)
      ? messages.filter(
          (m): m is { role: string; content: string } =>
            !!m &&
            typeof m === "object" &&
            typeof (m as { role?: unknown }).role === "string" &&
            typeof (m as { content?: unknown }).content === "string"
        )
      : []

    const response = await createTradeAnalysisCompletion(
      prompt,
      imageUrl,
      priorMessages
    )

    const rawResult = response.choices[0]?.message?.content
    const aiResult = normalizeAIProseResponse(rawResult) ?? rawResult?.trim()

    if (!aiResult) {
      console.error("[analyze-trade] Empty model response", {
        tradeId: String(tradeId),
        finishReason: response.choices[0]?.finish_reason,
      })
      return NextResponse.json(
        {
          error: "No response generated",
          reply:
            "The AI returned an empty response. Try again with a different question.",
          code: "empty_model_response",
        },
        { status: 502 }
      )
    }

    const { error: persistError } = await supabaseServiceRole
      .from("trades")
      .update({ ai_feedback: aiResult })
      .eq("id", String(tradeId))
      .eq("user_id", user.id)

    if (persistError) {
      console.error("[analyze-trade] ai_feedback persist failed", persistError)
      // Still return analysis to the client even if cache write fails.
    }

    return NextResponse.json({
      result: aiResult,
      reply: aiResult,
    })
  } catch (error) {
    const failure = analyzeTradeFailureFromError(error)
    console.error("[analyze-trade] Analysis error", {
      code: failure.code,
      tradeId: String(tradeId),
      userId: user.id,
      openAi: openAiErrorMetaForLog(error),
    })
    return NextResponse.json(
      {
        error: failure.error,
        reply: failure.reply,
        code: failure.code,
      },
      { status: failure.status }
    )
  }
}