import { NextResponse } from "next/server"
import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { openAiApiKey } from "@/lib/server/openAiRouteSupport"
import {
  GENERAL_TRADE_COACH_SYSTEM_PROMPT,
  buildGeneralTradeCoachPrompt,
} from "@/lib/generalTradeCoachPrompt"
import { buildAnalyzeTradeHistoryContext } from "@/lib/analyzeTradePrompt"
import { normalizeAIProseResponse } from "@/lib/normalizeAIGeneratedText"
import {
  consumeDurableUserRateLimit,
  rateLimitExceededResponse,
} from "@/lib/server/durableUserRateLimit"
import { requireAIFeatureEntitlement } from "@/lib/server/requireAIFeatureEntitlement"
import {
  createOpenAiChatCompletion,
  mapOpenAiErrorToHttp,
  trimConversationMessages,
} from "@/lib/server/openAiChatCompletion"
import { buildPortfolioAnalysisContext } from "@/lib/server/ai/aiPortfolioContextBuilder"
import type { AiPortfolioScope } from "@/lib/server/ai/aiConversationTypes"

export const runtime = "nodejs"
export const maxDuration = 60

export async function POST(req: Request) {
  const { user } = await getRouteUserAuth(req)
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }
  if (!openAiApiKey()) {
    return NextResponse.json({ error: "AI service unavailable" }, { status: 503 })
  }

  const entitlement = await requireAIFeatureEntitlement(user.id, {
    reply: "AI Analyst is a Pro feature.",
  })
  if (!entitlement.ok) {
    return entitlement.response
  }

  const rate = await consumeDurableUserRateLimit(user.id, "ai_analyze_trade")
  if (!rate.allowed) {
    return rateLimitExceededResponse(rate.retryAfterSec)
  }

  try {
    const body = await req.json()
    const question = typeof body?.question === "string" ? body.question.trim() : ""
    const messages = Array.isArray(body?.messages) ? body.messages : []
    if (!question) {
      return NextResponse.json({ error: "Missing question" }, { status: 400 })
    }

    const scope = body?.scope as AiPortfolioScope | undefined
    let historyText = "No logged trades yet."
    if (scope?.preset) {
      const portfolio = await buildPortfolioAnalysisContext(
        supabaseServiceRole,
        user.id,
        scope
      )
      historyText = `${portfolio.statisticsBlock}\n\nTRADE ROWS (CSV, bounded):\n${portfolio.tradesCsvBlock}`
      if (portfolio.limitations.length) {
        historyText += `\n\nLIMITATIONS:\n${portfolio.limitations.map((l) => `- ${l}`).join("\n")}`
      }
    } else {
      const { data: historyRows } = await supabaseServiceRole
        .from("trades")
        .select(
          "id, ticker, pnl, rr, direction, session, strategy, created_at, duration_seconds, duration_text, entry_time, exit_time"
        )
        .eq("user_id", user.id)
        .order("created_at", { ascending: false })
        .limit(120)

      const rows = historyRows ?? []
      const anchorId = rows.length > 0 ? String(rows[0].id ?? "") : ""
      const historyContext = anchorId
        ? buildAnalyzeTradeHistoryContext(rows, anchorId)
        : null
      historyText = historyContext?.summaryText ?? historyText
    }

    const prior = trimConversationMessages(
      messages.filter(
        (m: { role?: string; content?: string }) =>
          m &&
          (m.role === "user" || m.role === "assistant") &&
          typeof m.content === "string"
      )
    )

    const prompt = buildGeneralTradeCoachPrompt(historyText, question, prior)
    const openAiMessages = [
      { role: "system" as const, content: GENERAL_TRADE_COACH_SYSTEM_PROMPT },
      { role: "user" as const, content: prompt },
      ...prior.map((m: { role: string; content: string }) => ({
        role: m.role as "user" | "assistant",
        content: m.content,
      })),
    ]

    const completion = await createOpenAiChatCompletion({
      messages: openAiMessages,
      route: "general-trade-coach",
      userId: user.id,
      maxCompletionTokens: 900,
    })

    const reply =
      normalizeAIProseResponse(completion.content) ?? completion.content.trim()
    if (!reply) {
      return NextResponse.json({ error: "No response generated" }, { status: 500 })
    }

    return NextResponse.json({ reply, usage: completion.usage ?? null })
  } catch (error) {
    const mapped = mapOpenAiErrorToHttp(error)
    return NextResponse.json(mapped.body, { status: mapped.status })
  }
}