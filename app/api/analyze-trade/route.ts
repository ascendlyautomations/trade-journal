import OpenAI from "openai"
import { createClient } from "@supabase/supabase-js"
import { createServerClient } from "@supabase/ssr"
import { cookies } from "next/headers"

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY
})

// 🔥 SERVER-LEVEL SUPABASE CLIENT
const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const aiCallByUser = new Map<string, number>()

export async function POST(req: Request) {
  const cookieStore = await cookies()
  const supabaseAuth = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get: (name) => cookieStore.get(name)?.value,
      },
    }
  )
  const {
    data: { user },
  } = await supabaseAuth.auth.getUser()

  if (!user) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const lastCall = aiCallByUser.get(user.id) ?? 0
  if (Date.now() - lastCall < 3000) {
    return Response.json({ error: "Slow down" }, { status: 429 })
  }
  aiCallByUser.set(user.id, Date.now())

  const { trade, messages } = await req.json()
  const tradeId = trade?.id
  if (!tradeId) {
    return Response.json({ error: "Missing trade id" }, { status: 400 })
  }

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("is_pro, subscription_status")
    .eq("id", user.id)
    .single()

  if (profileError) {
    console.error("ERROR:", JSON.stringify(profileError, null, 2))
    return Response.json({ error: "Could not verify subscription" }, { status: 500 })
  }

  const pro =
    profile?.is_pro === true ||
    profile?.subscription_status === "active"
  if (!pro) {
    return Response.json(
      { error: "Pro required", reply: "AI Analyst is a Pro feature." },
      { status: 403 }
    )
  }

  const { data: existingTrade, error: tradeLookupError } = await supabase
    .from("trades")
    .select("id, user_id, image_url")
    .eq("id", tradeId)
    .single()

  if (tradeLookupError) {
    console.error("ERROR:", JSON.stringify(tradeLookupError, null, 2))
    return Response.json({ error: "Trade not found" }, { status: 404 })
  }

  if (!existingTrade || existingTrade.user_id !== user.id) {
    return Response.json({ error: "Forbidden" }, { status: 403 })
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
You are a professional trading coach.

Return:

Valid Setup:
...

What Could Be Improved:
- ...

Advice For Next Time:
- ...
`
      },
      {
        role: "user",
        content: [
          {
            type: "text",
            text: `
Ticker: ${trade.ticker}
PnL: ${trade.pnl}
RR: ${trade.rr}
Contracts: ${trade.contracts ?? "—"}
Notes: ${trade.notes}
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

  const reply = response.choices[0].message.content

  // 🔥 SAVE FEEDBACK (THIS NOW WORKS)
  await supabase
    .from("trades")
    .update({ ai_feedback: reply })
    .eq("id", tradeId)

  return Response.json({ reply })
}