import OpenAI from "openai"
import { createClient } from "@supabase/supabase-js"
import { NextResponse } from "next/server"
import {
  SCREENSHOT_TRADE_EXTRACT_SYSTEM_PROMPT,
  buildScreenshotTradeExtractUserPrompt,
} from "@/lib/screenshotTradeExtractPrompt"
import {
  validateScreenshotTradeExtractRequest,
  validateScreenshotTradeExtractionResponse,
  type ScreenshotTradeExtractRequestV1,
} from "@/lib/screenshotTradeExtractContract"
import {
  consumeDurableUserRateLimit,
  rateLimitExceededResponse,
} from "@/lib/server/durableUserRateLimit"
import { requireProEntitlement } from "@/lib/server/requireProEntitlement"
import type { Database } from "@/lib/database.types"

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
})

const MAX_IMAGE_BYTES = 2_500_000
const MAX_TOTAL_BYTES = 12_000_000
const AI_MODEL = "gpt-4o"

function decodeBase64Size(base64: string): number {
  const padding = base64.endsWith("==") ? 2 : base64.endsWith("=") ? 1 : 0
  return Math.floor((base64.length * 3) / 4) - padding
}

function validateImagePayload(request: ScreenshotTradeExtractRequestV1): string | null {
  let total = 0
  for (const shot of request.screenshots) {
    const size = decodeBase64Size(shot.base64)
    if (size <= 0) return "Unsupported image"
    if (size > MAX_IMAGE_BYTES) return "Screenshot too large"
    total += size
  }
  if (total > MAX_TOTAL_BYTES) return "Screenshot batch too large"
  return null
}

function buildImageContent(request: ScreenshotTradeExtractRequestV1) {
  return request.screenshots
    .sort((a, b) => a.index - b.index)
    .map((shot) => ({
      type: "image_url" as const,
      image_url: {
        url: `data:${shot.mimeType};base64,${shot.base64}`,
        detail: "high" as const,
      },
    }))
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

  const rate = await consumeDurableUserRateLimit(user.id, "ai_screenshot_extract")
  if (!rate.allowed) {
    return rateLimitExceededResponse(rate.retryAfterSec)
  }

  const entitlement = await requireProEntitlement(user.id, {
    reply:
      "Screenshot trade import with AI is a TraxPro feature. Upgrade your plan on the web to unlock it.",
  })
  if (!entitlement.ok) {
    return entitlement.response
  }

  try {
    const body = await req.json()
    const request = validateScreenshotTradeExtractRequest(body)
    if (!request) {
      return NextResponse.json({ error: "Invalid request" }, { status: 400 })
    }

    const imageError = validateImagePayload(request)
    if (imageError) {
      return NextResponse.json({ error: imageError }, { status: 400 })
    }

    const prompt = buildScreenshotTradeExtractUserPrompt(request)
    const images = buildImageContent(request)

    const completion = await openai.chat.completions.create({
      model: AI_MODEL,
      temperature: 0,
      max_tokens: 4000,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: SCREENSHOT_TRADE_EXTRACT_SYSTEM_PROMPT },
        {
          role: "user",
          content: [{ type: "text", text: prompt }, ...images],
        },
      ],
    })

    const rawContent = completion.choices[0]?.message?.content
    if (!rawContent) {
      return NextResponse.json({ error: "No extraction result" }, { status: 500 })
    }

    let parsed: unknown
    try {
      parsed = JSON.parse(rawContent)
    } catch {
      return NextResponse.json({ error: "Malformed AI response" }, { status: 500 })
    }

    const validated = validateScreenshotTradeExtractionResponse(parsed)
    if (!validated) {
      return NextResponse.json({ error: "Malformed AI response" }, { status: 500 })
    }

    if (
      validated.contentType === "none" ||
      validated.contentType === "unrelated"
    ) {
      return NextResponse.json({
        extraction: validated,
        error:
          validated.contentType === "unrelated"
            ? "No trade history detected in screenshot"
            : "No trades found in screenshot",
      })
    }

    if (validated.fills.length === 0 && validated.completedTrades.length === 0) {
      return NextResponse.json({
        extraction: validated,
        error: "No trades found in screenshot",
      })
    }

    return NextResponse.json({ extraction: validated })
  } catch (error) {
    console.error("[screenshot-extract] Extraction error:", error)
    const message =
      error instanceof Error && error.message.toLowerCase().includes("timeout")
        ? "AI analysis timed out. Try again."
        : "Screenshot extraction failed. Please try again."
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
