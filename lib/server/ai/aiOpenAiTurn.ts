import {
  getOpenAiClient,
  openAiAnalystModel,
  openAiApiKey,
  openAiRetryDelayMs,
  openAiErrorMetaForLog,
} from "@/lib/server/openAiRouteSupport"
import { normalizeAIProseResponse } from "@/lib/normalizeAIGeneratedText"
import { tradeScreenshotPublicUrl } from "@/lib/storagePublicUrl"
import type { ChatCompletionMessageParam } from "openai/resources/chat/completions"

export type OpenAiTurnMessage = {
  role: "user" | "assistant" | "system"
  content: string
  imageUrls?: string[]
}

export type OpenAiImagePart = {
  kind: "image_url"
  url: string
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

function userContentParts(text: string, imageUrls: string[]) {
  const urls = imageUrls.filter((u) => u.startsWith("http"))
  if (urls.length === 0) return text
  return [
    { type: "text" as const, text },
    ...urls.map((url) => ({
      type: "image_url" as const,
      image_url: { url },
    })),
  ]
}

export async function runTradeAiCompletion(input: {
  systemPrompt: string
  primaryUserPrompt: string
  primaryImages?: OpenAiImagePart[]
  priorMessages?: OpenAiTurnMessage[]
  maxContextChars?: number
}): Promise<{
  reply: string
  usage: {
    model: string
    promptTokens: number | null
    completionTokens: number | null
    totalTokens: number | null
  }
}> {
  if (!openAiApiKey()) {
    throw Object.assign(new Error("OPENAI_API_KEY missing"), {
      code: "openai_not_configured",
    })
  }
  const openai = getOpenAiClient()
  if (!openai) {
    throw Object.assign(new Error("OPENAI_API_KEY missing"), {
      code: "openai_not_configured",
    })
  }

  const maxChars = input.maxContextChars ?? 120_000
  let prior = input.priorMessages ?? []
  const priorLen = prior.reduce((s, m) => s + m.content.length, 0)
  if (input.primaryUserPrompt.length + priorLen > maxChars) {
    while (
      prior.length > 2 &&
      input.primaryUserPrompt.length +
        prior.reduce((s, m) => s + m.content.length, 0) >
        maxChars
    ) {
      prior = prior.slice(2)
    }
  }

  const primaryUrls = (input.primaryImages ?? [])
    .map((p) => p.url)
    .filter((u) => u.startsWith("http"))

  const buildMessages = (includePrimaryImages: boolean): ChatCompletionMessageParam[] => {
    const history: ChatCompletionMessageParam[] = prior.map((m) => {
      if (m.role === "assistant") {
        return { role: "assistant", content: m.content }
      }
      const content =
        (m.imageUrls?.length ?? 0) > 0
          ? userContentParts(m.content, m.imageUrls ?? [])
          : m.content
      return { role: "user", content }
    })
    return [
      { role: "system", content: input.systemPrompt },
      {
        role: "user",
        content: userContentParts(
          input.primaryUserPrompt,
          includePrimaryImages ? primaryUrls : []
        ),
      },
      ...history,
    ]
  }

  const model = openAiAnalystModel()
  const wantsImages =
    primaryUrls.length > 0 || prior.some((m) => (m.imageUrls?.length ?? 0) > 0)

  const run = (withImages: boolean) =>
    openai.chat.completions.create({
      model,
      messages: buildMessages(withImages),
    })

  let response
  try {
    response = await runWithTransientRetry(() => run(wantsImages))
  } catch (error) {
    if (!wantsImages || !isOpenAiImageFetchError(error)) throw error
    console.warn("[ai] Image unavailable; text-only analysis.", {
      openAi: openAiErrorMetaForLog(error),
    })
    response = await runWithTransientRetry(() => run(false))
  }

  const raw = response.choices[0]?.message?.content
  const reply = normalizeAIProseResponse(raw) ?? raw?.trim()
  if (!reply) {
    throw Object.assign(new Error("empty_model_response"), {
      code: "empty_model_response",
    })
  }

  return {
    reply,
    usage: {
      model,
      promptTokens: response.usage?.prompt_tokens ?? null,
      completionTokens: response.usage?.completion_tokens ?? null,
      totalTokens: response.usage?.total_tokens ?? null,
    },
  }
}

export function publicImageUrlFromStoragePath(
  path: string | null | undefined
): string | null {
  return tradeScreenshotPublicUrl(path)
}