import OpenAI from "openai"
import { createClient } from "@supabase/supabase-js"

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY
})

// 🔥 SERVER-LEVEL SUPABASE CLIENT
const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

export async function POST(req: Request) {
  const { trade, messages } = await req.json()

  const imageUrl = trade.image_url
    ? `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/screenshots/${trade.image_url}`
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
    .eq("id", trade.id)

  return Response.json({ reply })
}