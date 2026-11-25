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

export type OpenAiErrorMeta = {
  httpStatus?: number
  type?: string
  code?: string
  requestId?: string
}

/** Safe fields for server logs (no API keys, no long upstream copy). */
export function openAiErrorMetaForLog(error: unknown): OpenAiErrorMeta {
  if (!error || typeof error !== "object") return {}
  const e = error as {
    status?: number
    code?: string
    type?: string
    requestID?: string
    error?: { type?: string; code?: string; message?: string }
  }
  return {
    httpStatus: e.status,
    type: e.type ?? e.error?.type,
    code: e.code ?? e.error?.code,
    requestId: e.requestID,
  }
}

export type AnalyzeTradeFailurePayload = {
  status: number
  error: string
  reply: string
  code: string
}

function isQuotaExhausted(meta: OpenAiErrorMeta): boolean {
  const type = (meta.type ?? "").toLowerCase()
  const code = (meta.code ?? "").toLowerCase()
  return (
    type === "insufficient_quota" ||
    code === "insufficient_quota" ||
    code === "credit_balance_exhausted" ||
    code.includes("insufficient_quota") ||
    code.includes("credit_balance")
  )
}

function isRateLimited(meta: OpenAiErrorMeta): boolean {
  const type = (meta.type ?? "").toLowerCase()
  const code = (meta.code ?? "").toLowerCase()
  return (
    type === "rate_limit_exceeded" ||
    type === "tokens" ||
    code === "rate_limit_exceeded" ||
    code.includes("rate_limit_exceeded")
  )
}

export function analyzeTradeFailureFromError(error: unknown): AnalyzeTradeFailurePayload {
  if (!openAiApiKey()) {
    return {
      status: 503,
      code: "openai_not_configured",
      error: "AI service unavailable",
      reply:
        "Trade AI is temporarily unavailable on the server. Our team has been notified. Please try again later.",
    }
  }

  const meta = openAiErrorMetaForLog(error)

  if (meta.httpStatus === 401 || meta.code === "invalid_api_key") {
    return {
      status: 503,
      code: "openai_auth_failed",
      error: "AI service misconfigured",
      reply:
        "Trade AI could not reach the analysis service. Please try again later.",
    }
  }

  if (isQuotaExhausted(meta)) {
    return {
      status: 503,
      code: "openai_quota_exhausted",
      error: "AI service unavailable",
      reply:
        "Trade AI is temporarily unavailable. The analysis service needs to be restored on our side. Please try again later or contact support if this continues.",
    }
  }

  if (meta.httpStatus === 429 && isRateLimited(meta)) {
    return {
      status: 503,
      code: "openai_rate_limited",
      error: "AI service busy",
      reply:
        "Trade AI is busy right now. Wait a moment and try your analysis again.",
    }
  }

  if (meta.httpStatus === 429) {
    return {
      status: 503,
      code: "openai_upstream_throttled",
      error: "AI service busy",
      reply:
        "Trade AI could not complete the request right now. Wait a moment and try again.",
    }
  }

  if (
    meta.httpStatus === 400 &&
    (meta.code?.includes("invalid") || meta.type === "invalid_request_error")
  ) {
    return {
      status: 503,
      code: "openai_request_invalid",
      error: "AI request rejected",
      reply:
        "We couldn't run this analysis with the current trade data. Try again or contact support if it persists.",
    }
  }

  return {
    status: 500,
    code: "analysis_failed",
    error: "Analysis failed",
    reply:
      "We couldn't complete the analysis right now. Please try again in a moment.",
  }
}

const TRANSIENT_OPENAI_RETRY_MS = 1_200

export function openAiRetryDelayMs(error: unknown): number | null {
  const meta = openAiErrorMetaForLog(error)
  if (meta.httpStatus === 429 && isRateLimited(meta) && !isQuotaExhausted(meta)) {
    return TRANSIENT_OPENAI_RETRY_MS
  }
  return null
}