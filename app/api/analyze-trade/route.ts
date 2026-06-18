import OpenAI from "openai"
import { createClient } from "@supabase/supabase-js"
import { NextResponse } from "next/server"

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
})

// 🔥 SERVER-LEVEL SUPABASE CLIENT
const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const aiCallByUser = new Map<string, number>()

function resolveScreenshotPublicUrl(imagePath: string | null | undefined) {
  if (!imagePath?.trim()) return null
  if (imagePath.startsWith("http://") || imagePath.startsWith("https://")) {
    return imagePath
  }
  return `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/screenshots/${imagePath}`
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

function buildTradePrompt(trade: Record<string, unknown>) {
  return `
You are a strict trading performance coach.

You must analyze this trade using ONLY the data provided.
Do NOT assume anything that is not explicitly given.

Be critical, direct, and specific. Avoid generic praise.

---

TRADE DATA:

P&L: ${trade.pnl}
RR: ${trade.rr}
Direction: ${trade.direction}

Entry Price: ${trade.entry_price}
Exit Price: ${trade.exit_price}

Trader Notes:
${trade.notes || "None provided"}

Top Confluences:
${trade.confluences || trade.top_confluences || "None provided"}

Mistakes:
${trade.mistakes || "None provided"}

Psychology:
${trade.psychology || trade.psychology_notes || "None provided"}

---

RULES:

* If notes are empty → explicitly say the trade lacks context
* If mistakes are empty → question whether the trader reviewed the trade properly
* Do NOT assume strategy (e.g. Fibonacci, breakout) unless stated
* Do NOT praise without explanation
* If RR is high → evaluate whether it was skill or luck
* If trade is profitable → still identify flaws

---

OUTPUT FORMAT:

1. EXECUTION
   Was the entry and exit actually justified based on the trader's notes?

2. RISK MANAGEMENT
   Was the RR realistic and planned, or just outcome-based?

3. PSYCHOLOGY
   What does the trader's input reveal about discipline or emotion?

4. WHAT YOU DID WRONG
   Be direct. Identify real issues.

5. WHAT TO IMPROVE
   Give specific, actionable improvements.

6. FINAL VERDICT
   Short, blunt summary (1–2 sentences max).

---

Be concise. Be honest. Be critical.
`
}

function buildOpenAiMessages(
  prompt: string,
  imageUrl: string | null,
  priorMessages: Array<{ role: string; content: string }> = []
) {
  return [
    {
      role: "system" as const,
      content:
        "Follow the user message: use only supplied trade fields, obey the rules and numbered output format.",
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
  console.log("AI API HIT")
  const token = req.headers.get("authorization")?.replace("Bearer ", "")

  const supabase = createClient(
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
    console.error("AI AUTH FAILED")
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 })
  }
  console.log("AI AUTH USER:", user.id)

  const lastCall = aiCallByUser.get(user.id) ?? 0
  if (Date.now() - lastCall < 3000) {
    return NextResponse.json({ error: "Slow down" }, { status: 429 })
  }
  aiCallByUser.set(user.id, Date.now())

  try {
    const body = await req.json()
    console.log("AI BACKEND INPUT:", body)
    const { trade, messages } = body
    const tradeId = trade?.id
    if (!tradeId) {
      return NextResponse.json({ error: "Missing trade id" }, { status: 400 })
    }

    const { data: profile, error: profileError } = await supabaseAdmin
      .from("profiles")
      .select("is_pro, subscription_status")
      .eq("id", user.id)
      .single()

    if (profileError) {
      console.error("ERROR:", JSON.stringify(profileError, null, 2))
      return NextResponse.json(
        { error: "Could not verify subscription" },
        { status: 500 }
      )
    }

    const pro =
      profile?.is_pro === true ||
      profile?.subscription_status === "active"
    if (!pro) {
      return NextResponse.json(
        { error: "Pro required", reply: "AI Analyst is a Pro feature." },
        { status: 403 }
      )
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
    const prompt = buildTradePrompt(trade)
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
