import OpenAI from "openai"
import { createClient } from "@supabase/supabase-js"
import { NextResponse } from "next/server"
import {
  ANALYZE_TRADE_SYSTEM_PROMPT,
  buildAnalyzeTradeHistoryContext,
  buildTradeAnalysisPrompt,
} from "@/lib/analyzeTradePrompt"
import { tradeScreenshotPublicUrl } from "@/lib/storagePublicUrl"
import {
  consumeDurableUserRateLimit,
  rateLimitExceededResponse,
} from "@/lib/server/durableUserRateLimit"
import { requireProEntitlement } from "@/lib/server/requireProEntitlement"
import type { Database } from "@/lib/database.types"

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
})

// 🔥 SERVER-LEVEL SUPABASE CLIENT
const supabaseAdmin = createClient<Database>(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

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
  const run = (withImage: boolean) =>
    openai.chat.completions.create({
      model: "gpt-4o",
      messages: buildOpenAiMessages(
        prompt,
        withImage ? imageUrl : null,
        priorMessages
      ),
    })

  if (!imageUrl) {
    return run(false)
  }

  try {
    return await run(true)
  } catch (error) {
    if (!isOpenAiImageFetchError(error)) {
      throw error
    }
    console.warn(
      "[analyze-trade] Screenshot unavailable. Proceeding with trade-only analysis.",
      error
    )
    return run(false)
  }
}

export async function POST(req: Request) {
  const token = req.headers.get("authorization")?.replace("Bearer ", "")

  const supabase = createClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      global: {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      },
    }
  )
  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }

  const rate = await consumeDurableUserRateLimit(user.id, "ai_analyze_trade")
  if (!rate.allowed) {
    return rateLimitExceededResponse(rate.retryAfterSec)
  }

  try {
    const body = await req.json()
    const { trade, messages } = body
    const tradeId = trade?.id
    if (!tradeId) {
      return NextResponse.json({ error: "Missing trade id" }, { status: 400 })
    }

    const entitlement = await requireProEntitlement(user.id, {
      reply: "AI Analyst is a Pro feature.",
    })
    if (!entitlement.ok) {
      return entitlement.response
    }

    const { data: existingTrade, error: tradeLookupError } = await supabaseAdmin
      .from("trades")
      .select("id, user_id, image_url")
      .eq("id", tradeId)
      .single()

    if (tradeLookupError) {
      console.error("ERROR:", JSON.stringify(tradeLookupError, null, 2))
      return NextResponse.json({ error: "Trade not found" }, { status: 404 })
    }

    if (!existingTrade || existingTrade.user_id !== user.id) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 })
    }

    const imageUrl = resolveScreenshotPublicUrl(existingTrade.image_url)

    const { data: historyRows } = await supabaseAdmin
      .from("trades")
      .select(
        "id, ticker, pnl, rr, direction, session, strategy, created_at, duration_seconds, duration_text, entry_time, exit_time"
      )
      .eq("user_id", user.id)
      .order("created_at", { ascending: false })
      .limit(120)

    const historyContext = buildAnalyzeTradeHistoryContext(
      historyRows ?? [],
      String(tradeId)
    )
    const prompt = buildTradeAnalysisPrompt(trade, historyContext, {
      hasScreenshot: Boolean(imageUrl),
    })
    const priorMessages = Array.isArray(messages) ? messages : []

    const response = await createTradeAnalysisCompletion(
      prompt,
      imageUrl,
      priorMessages
    )

    const aiResult = response.choices[0].message.content

    await supabaseAdmin
      .from("trades")
      .update({ ai_feedback: aiResult })
      .eq("id", tradeId)
      .eq("user_id", user.id)

    if (aiResult) {
      return NextResponse.json({
        result: aiResult,
        reply: aiResult,
      })
    }

    return NextResponse.json(
      { error: "No response generated" },
      { status: 500 }
    )
  } catch (error) {
    console.error("[analyze-trade] Analysis error:", error)
    return NextResponse.json(
      {
        error: "Analysis failed. Please try again.",
        reply:
          "We couldn't complete the analysis right now. Please try again in a moment.",
      },
      { status: 500 }
    )
  }
}
