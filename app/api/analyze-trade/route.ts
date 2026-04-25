import OpenAI from "openai"
import { createClient } from "@supabase/supabase-js"
import { NextResponse } from "next/server"

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY
})

// 🔥 SERVER-LEVEL SUPABASE CLIENT
const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const aiCallByUser = new Map<string, number>()

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

  const { trade, messages } = await req.json()
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
    return NextResponse.json({ error: "Could not verify subscription" }, { status: 500 })
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

  const imageUrl = existingTrade.image_url
    ? `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/screenshots/${existingTrade.image_url}`
    : null

  const response = await openai.chat.completions.create({
    model: "gpt-4o",
    messages: [
      {
        role: "system",
        content: `
You are an elite trading performance analyst.

You specialize in:
- futures trading (NQ, ES, MNQ)
- risk management
- trade execution
- trader psychology
- consistency and discipline

Your job is to analyze a trader's executed trade and give direct, actionable feedback.

Give a structured breakdown:

1. EXECUTION QUALITY
- Was entry logical?
- Was exit optimal or premature?
- Any signs of chasing or hesitation?

2. RISK MANAGEMENT
- Was the trade size appropriate?
- Was the loss controlled properly?
- Was RR acceptable?

3. PSYCHOLOGY
- What does this trade suggest about the trader’s mindset?
- Any signs of fear, greed, revenge trading, hesitation?

4. WHAT WAS DONE WELL
- Highlight at least one positive behavior

5. WHAT TO IMPROVE
- Give specific, actionable improvements

6. FINAL VERDICT
- 1–2 sentence blunt summary (like a coach)

STYLE:
- Be direct, not generic
- Avoid vague advice like "manage risk better"
- Speak like a trading coach reviewing a real trade
- Keep it concise but insightful
`
      },
      {
        role: "user",
        content: [
          {
            type: "text",
            text: `
TRADE DATA:

- Symbol: ${trade.symbol ?? trade.ticker ?? "Unknown"}
- Direction: ${trade.direction ?? "Unknown"}
- Entry Price: ${trade.entry_price ?? "N/A"}
- Exit Price: ${trade.exit_price ?? "N/A"}
- PnL: ${trade.pnl ?? "N/A"}
- Risk Reward (RR): ${trade.rr ?? "N/A"}
- Contracts: ${trade.contracts ?? "N/A"}
- Session: ${trade.session ?? "N/A"}
- Entry Time: ${trade.entry_time ?? "N/A"}
- Exit Time: ${trade.exit_time ?? "N/A"}
- Notes: ${trade.notes || "None"}
`
          },
          ...(imageUrl
            ? [{ type: "image_url", image_url: { url: imageUrl } }]
            : [])
        ]
      },
      ...(messages || [])
    ]
  })

  const aiResult = response.choices[0].message.content

  // 🔥 SAVE FEEDBACK (THIS NOW WORKS)
  await supabaseAdmin
    .from("trades")
    .update({ ai_feedback: aiResult })
    .eq("id", tradeId)

  if (aiResult) {
    return NextResponse.json({
      result: aiResult,
      reply: aiResult
    })
  }

  return NextResponse.json(
    { error: "No response generated" },
    { status: 500 }
  )
}