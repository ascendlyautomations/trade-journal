import OpenAI from "openai"
import { createClient } from "@supabase/supabase-js"
import { NextResponse } from "next/server"
import {
  PSYCHOLOGY_COACH_SYSTEM_PROMPT,
  buildPsychologyCoachUserPrompt,
  type PsychologyCoachFactsPayload,
} from "@/lib/psychologyCoachPrompt"
import type { Database } from "@/lib/database.types"

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
})

const supabaseAdmin = createClient<Database>(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const aiCallByUser = new Map<string, number>()

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

  const lastCall = aiCallByUser.get(user.id) ?? 0
  if (Date.now() - lastCall < 3000) {
    return NextResponse.json({ error: "Slow down" }, { status: 429 })
  }
  aiCallByUser.set(user.id, Date.now())

  try {
    const body = await req.json()
    const facts = body?.facts as PsychologyCoachFactsPayload | undefined
    const mode = typeof body?.mode === "string" ? body.mode : "explain"
    const messages = Array.isArray(body?.messages) ? body.messages : []

    if (!facts || typeof facts !== "object") {
      return NextResponse.json({ error: "Missing psychology facts" }, { status: 400 })
    }

    // Owner-only — facts are always computed client-side for auth.uid(); reject cross-user payloads.
    if (body?.userId && body.userId !== user.id) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 })
    }

    const prompt = buildPsychologyCoachUserPrompt(facts, mode, messages)

    const completion = await openai.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        { role: "system", content: PSYCHOLOGY_COACH_SYSTEM_PROMPT },
        { role: "user", content: prompt },
        ...messages.map((message: { role: string; content: string }) => ({
          role: message.role as "user" | "assistant",
          content: message.content,
        })),
      ],
      temperature: 0.4,
      max_tokens: 800,
    })

    const reply = completion.choices[0]?.message?.content?.trim()
    if (!reply) {
      return NextResponse.json({ error: "No response generated" }, { status: 500 })
    }

    const factsHash = typeof facts.factsHash === "string" ? facts.factsHash : null
    if (factsHash && mode === "summary") {
      await supabaseAdmin.from("psychology_coach_snapshots").upsert(
        {
          user_id: user.id,
          facts_hash: factsHash,
          summary_json: facts,
          ai_explanation: reply,
          generated_at: new Date().toISOString(),
        },
        { onConflict: "user_id" }
      )
    }

    return NextResponse.json({ reply })
  } catch (error) {
    console.error("[psychology-coach]", error)
    return NextResponse.json(
      { error: "Psychology coach unavailable. Your analytics still work offline." },
      { status: 500 }
    )
  }
}
