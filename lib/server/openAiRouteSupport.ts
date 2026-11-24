import OpenAI from "openai"

export function openAiApiKey(): string | null {
  const key = process.env.OPENAI_API_KEY?.trim()
  return key && key.length > 0 ? key : null
}

let cachedClient: OpenAI | null = null
let cachedKey: string | null = null

export function getOpenAiClient(): OpenAI | null {
  const key = openAiApiKey()
  if (!key) return null
  if (!cachedClient || cachedKey !== key) {
    cachedClient = new OpenAI({ apiKey: key })
    cachedKey = key
  }
  return cachedClient
}

export type AnalyzeTradeFailurePayload = {
  status: number
  error: string
  reply: string
  code: string
  detail?: string
}

export function analyzeTradeFailureFromError(error: unknown): AnalyzeTradeFailurePayload {
  if (!openAiApiKey()) {
    return {
      status: 503,
      code: "openai_not_configured",
      error: "AI service unavailable",
      reply:
        "Trade AI is temporarily unavailable on the server. Our team has been notified. Please try again later.",
      detail: "OPENAI_API_KEY is not set in the deployment environment.",
    }
  }

  if (error && typeof error === "object") {
    const e = error as {
      status?: number
      code?: string
      message?: string
      error?: { message?: string; code?: string; type?: string }
    }
    const message = `${e.message ?? ""} ${e.error?.message ?? ""}`.trim()
    const apiCode = `${e.code ?? ""} ${e.error?.code ?? ""}`.toLowerCase()
    const status = e.status

    if (status === 401 || apiCode.includes("invalid_api_key")) {
      return {
        status: 503,
        code: "openai_auth_failed",
        error: "AI service misconfigured",
        reply:
          "Trade AI could not reach the analysis service. Please try again later.",
        detail: message || "OpenAI rejected the API key.",
      }
    }

    if (status === 429 || apiCode.includes("rate_limit")) {
      return {
        status: 503,
        code: "openai_rate_limited",
        error: "AI service busy",
        reply:
          "Trade AI is busy right now. Wait a moment and try your analysis again.",
        detail: message,
      }
    }

    if (
      status === 400 &&
      (apiCode.includes("invalid") || message.toLowerCase().includes("model"))
    ) {
      return {
        status: 503,
        code: "openai_request_invalid",
        error: "AI request rejected",
        reply:
          "We couldn't run this analysis with the current trade data. Try again or contact support if it persists.",
        detail: message,
      }
    }
  }

  return {
    status: 500,
    code: "analysis_failed",
    error: "Analysis failed",
    reply:
      "We couldn't complete the analysis right now. Please try again in a moment.",
    detail: error instanceof Error ? error.message : String(error),
  }
}