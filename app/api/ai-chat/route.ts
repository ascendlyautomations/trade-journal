import OpenAI from "openai"
import { getRouteUser } from "@/app/api/_lib/getRouteUser"

export async function POST(req: Request) {
  try {
    const user = await getRouteUser(req)
    if (!user) {
      console.warn("[api/ai-chat] unauthorized request", {
        hasAuthorization: Boolean(req.headers.get("authorization")),
        userAgent: req.headers.get("user-agent") ?? undefined,
      })
      return Response.json({ error: "Unauthorized" }, { status: 401 })
    }

    const apiKey = process.env.OPENAI_API_KEY
    if (!apiKey) {
      return Response.json(
        { error: "OpenAI is not configured." },
        { status: 500 }
      )
    }

    const body = await req.json().catch(() => null)
    const message =
      typeof body?.message === "string" ? body.message.trim() : ""
    if (!message) {
      return Response.json({ error: "Message is required." }, { status: 400 })
    }

    const openai = new OpenAI({ apiKey })

    const completion = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        {
          role: "system",
          content: `
You are a helpful assistant for TradeTrax.

Speak casually and clearly like a real person.
DO NOT use markdown (** or bullet symbols).
Keep responses short and easy to read.

Explain things naturally like:
"Yeah, you can track trades with screenshots and see your stats like win rate and P&L."

Avoid long lists unless necessary.
`.trim(),
        },
        {
          role: "user",
          content: message,
        },
      ],
    })

    const reply = completion.choices[0]?.message?.content ?? ""
    return Response.json({ reply })
  } catch (e) {
    console.error("ai-chat error:", e)
    return Response.json(
      { error: "Could not get a response. Try again." },
      { status: 500 }
    )
  }
}
