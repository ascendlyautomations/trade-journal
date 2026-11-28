import type OpenAI from "openai"
import {
  analyzeTradeFailureFromError,
  getOpenAiClient,
  openAiAnalystModel,
  openAiErrorMetaForLog,
  openAiRetryDelayMs,
} from "@/lib/server/openAiRouteSupport"

export type OpenAiChatMessage = {
  role: "system" | "user" | "assistant"
  content: string
}

export type OpenAiChatCompletionOptions = {
  messages: OpenAiChatMessage[]
  temperature?: number
  maxCompletionTokens?: number
  route: string
  userId?: string
}

export type OpenAiChatCompletionResult = {
  content: string
  usage?: {
    prompt_tokens?: number
    completion_tokens?: number
    total_tokens?: number
  }
  finishReason?: string | null
}

const DEFAULT_MAX_COMPLETION_TOKENS = 1200
const MAX_INPUT_CHARS = 120_000
const MAX_CONVERSATION_TURNS = 24

export function openAiCoachModel(): string {
  return openAiAnalystModel()
}

export function trimConversationMessages(
  messages: Array<{ role: string; content: string }>,
  maxTurns = MAX_CONVERSATION_TURNS
): Array<{ role: string; content: string }> {
  if (messages.length <= maxTurns) return messages
  return messages.slice(messages.length - maxTurns)
}

export function capPromptSize(text: string, maxChars = MAX_INPUT_CHARS): string {
  if (text.length <= maxChars) return text
  return `${text.slice(0, maxChars)}\n\n[Context truncated for request size limits.]`
}

function logOpenAiTokenUsage(
  route: string,
  userId: string | undefined,
  usage: OpenAiChatCompletionResult["usage"]
) {
  if (!usage) return
  console.info(`[${route}] openai_usage`, {
    userId: userId ?? "unknown",
    promptTokens: usage.prompt_tokens,
    completionTokens: usage.completion_tokens,
    totalTokens: usage.total_tokens,
  })
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

export async function createOpenAiChatCompletion(
  options: OpenAiChatCompletionOptions
): Promise<OpenAiChatCompletionResult> {
  const openai = getOpenAiClient()
  if (!openai) {
    throw Object.assign(new Error("OPENAI_API_KEY missing"), {
      code: "openai_not_configured",
    })
  }

  const messages = options.messages.map((message) => ({
    role: message.role,
    content: capPromptSize(message.content),
  }))

  const maxCompletionTokens =
    options.maxCompletionTokens ?? DEFAULT_MAX_COMPLETION_TOKENS

  const response = await runWithTransientRetry(() =>
    openai.chat.completions.create({
      model: openAiCoachModel(),
      messages,
      temperature: options.temperature ?? 0.35,
      max_completion_tokens: maxCompletionTokens,
    })
  )

  logOpenAiTokenUsage(options.route, options.userId, response.usage)

  const content = response.choices[0]?.message?.content?.trim() ?? ""
  return {
    content,
    usage: response.usage,
    finishReason: response.choices[0]?.finish_reason,
  }
}

export function mapOpenAiErrorToHttp(error: unknown): {
  status: number
  body: { error: string; reply?: string; code?: string }
} {
  const failure = analyzeTradeFailureFromError(error)
  console.error("[openai-chat] failure", { openAi: openAiErrorMetaForLog(error) })
  return {
    status: failure.status,
    body: {
      error: failure.error,
      reply: failure.reply,
      code: failure.code,
    },
  }
}