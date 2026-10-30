/**
 * Bounded retries for idempotent server-side Supabase / fetch reads.
 * Extends PostgREST schema-cache transients with network/socket failures.
 */

import {
  isNonRetryablePostgrestError,
  isTransientPostgrestError,
  type PostgrestLikeError,
} from "./postgrestTransientRetry.ts"

export type ServerReadErrorClassification =
  | "transient_network"
  | "transient_postgrest"
  | "timeout"
  | "non_retryable"
  | "unknown"

export type ServerReadLogOutcome = {
  operation: string
  durationMs: number
  attempts: number
  outcome: "success" | "partial" | "failure"
  errorClass?: ServerReadErrorClassification
  correlationId?: string | null
  detail?: string
  rows?: number
}

export class SupabaseReadError extends Error {
  readonly classification: ServerReadErrorClassification
  readonly code: string | null
  readonly causeError: unknown

  constructor(
    message: string,
    classification: ServerReadErrorClassification,
    options?: { code?: string | null; cause?: unknown }
  ) {
    super(message)
    this.name = "SupabaseReadError"
    this.classification = classification
    this.code = options?.code ?? null
    this.causeError = options?.cause ?? null
  }
}

function errorCode(error: unknown): string | null {
  if (!error || typeof error !== "object") return null
  const code = (error as PostgrestLikeError).code
  return code != null ? String(code) : null
}

function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message
  if (error && typeof error === "object" && "message" in error) {
    return String((error as { message?: unknown }).message ?? "")
  }
  return String(error ?? "")
}

function walkErrorChain(error: unknown, maxDepth = 4): unknown[] {
  const chain: unknown[] = []
  let cur: unknown = error
  for (let i = 0; i < maxDepth && cur; i++) {
    chain.push(cur)
    if (cur instanceof Error && "cause" in cur && cur.cause) {
      cur = cur.cause
      continue
    }
    if (cur && typeof cur === "object" && "cause" in cur) {
      const next = (cur as { cause?: unknown }).cause
      if (next) {
        cur = next
        continue
      }
    }
    break
  }
  return chain
}

function chainText(error: unknown): string {
  return walkErrorChain(error)
    .map((e) => errorMessage(e))
    .join(" ")
    .toLowerCase()
}

function chainCodes(error: unknown): string[] {
  const codes: string[] = []
  for (const link of walkErrorChain(error)) {
    const code = errorCode(link)
    if (code) codes.push(code.toUpperCase())
    if (link && typeof link === "object") {
      const errno = (link as { errno?: unknown }).errno
      if (typeof errno === "string") codes.push(errno.toUpperCase())
      const name = (link as { name?: unknown }).name
      if (typeof name === "string") codes.push(name.toUpperCase())
    }
  }
  return codes
}

export function isAbortError(error: unknown): boolean {
  return (
    (error instanceof DOMException && error.name === "AbortError") ||
    (error instanceof Error && error.name === "AbortError")
  )
}

export function isTransientNetworkError(error: unknown): boolean {
  if (isTransientPostgrestError(error)) return false
  const msg = chainText(error)
  const codes = chainCodes(error)

  if (msg.includes("fetch failed")) return true
  if (msg.includes("other side closed")) return true
  if (msg.includes("socket hang up")) return true
  if (msg.includes("network error")) return true
  if (msg.includes("econnreset")) return true
  if (msg.includes("etimedout")) return true
  if (msg.includes("eai_again")) return true

  for (const c of codes) {
    if (
      c === "UND_ERR_SOCKET" ||
      c === "UND_ERR_CONNECT_TIMEOUT" ||
      c === "UND_ERR_HEADERS_TIMEOUT" ||
      c === "UND_ERR_BODY_TIMEOUT" ||
      c === "ECONNRESET" ||
      c === "ETIMEDOUT" ||
      c === "EAI_AGAIN"
    ) {
      return true
    }
  }

  const httpLike = errorCode(error)
  if (httpLike === "502" || httpLike === "503" || httpLike === "504") return true
  if (/\b(502|503|504)\b/.test(msg)) return true

  return false
}

export function classifyServerReadError(
  error: unknown
): ServerReadErrorClassification {
  if (isNonRetryablePostgrestError(error)) return "non_retryable"
  if (isAbortError(error)) {
    const msg = errorMessage(error).toLowerCase()
    if (msg.includes("timeout") || msg.includes("timed out")) return "timeout"
    return "non_retryable"
  }
  if (isTransientPostgrestError(error)) return "transient_postgrest"
  if (isTransientNetworkError(error)) return "transient_network"
  return "unknown"
}

export function isTransientServerReadError(error: unknown): boolean {
  const kind = classifyServerReadError(error)
  return kind === "transient_network" || kind === "transient_postgrest"
}

export function isNonRetryableServerReadError(error: unknown): boolean {
  if (isNonRetryablePostgrestError(error)) return true
  const kind = classifyServerReadError(error)
  if (kind === "non_retryable") return true
  if (kind === "unknown") return true
  return false
}

export function logServerReadOutcome(meta: ServerReadLogOutcome): void {
  const payload = {
    operation: meta.operation,
    durationMs: Math.round(meta.durationMs),
    attempts: meta.attempts,
    outcome: meta.outcome,
    ...(meta.errorClass ? { errorClass: meta.errorClass } : {}),
    ...(meta.correlationId ? { correlationId: meta.correlationId } : {}),
    ...(meta.rows != null ? { rows: meta.rows } : {}),
    ...(meta.detail ? { detail: meta.detail.slice(0, 240) } : {}),
  }
  if (meta.outcome === "failure") {
    console.error("[server-read]", payload)
  } else if (meta.outcome === "partial") {
    console.warn("[server-read]", payload)
  } else {
    console.info("[server-read]", payload)
  }
}

function sleep(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(new DOMException("Aborted", "AbortError"))
      return
    }
    const timer = globalThis.setTimeout(resolve, ms)
    signal?.addEventListener(
      "abort",
      () => {
        globalThis.clearTimeout(timer)
        reject(new DOMException("Aborted", "AbortError"))
      },
      { once: true }
    )
  })
}

export type ServerReadRetryMeta = {
  attempt: number
  maxAttempts: number
  delayMs: number
  classification: ServerReadErrorClassification
  code: string | null
}

export type WithServerReadRetryOptions = {
  maxAttempts?: number
  baseDelayMs?: number
  maxDelayMs?: number
  signal?: AbortSignal
  operation?: string
  onRetry?: (meta: ServerReadRetryMeta) => void
}

/** Idempotent read: exponential backoff + jitter; skips permanent failures. */
export async function withServerReadRetry<T>(
  fn: (attempt: number, signal?: AbortSignal) => Promise<T>,
  options?: WithServerReadRetryOptions
): Promise<T> {
  const maxAttempts = Math.max(1, options?.maxAttempts ?? 4)
  const baseDelayMs = options?.baseDelayMs ?? 120
  const maxDelayMs = options?.maxDelayMs ?? 2_000
  let lastError: unknown

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    if (options?.signal?.aborted) {
      throw new DOMException("Aborted", "AbortError")
    }
    try {
      return await fn(attempt, options?.signal)
    } catch (err) {
      lastError = err
      const classification = classifyServerReadError(err)
      const code = errorCode(err)
      const retryable = isTransientServerReadError(err)
      if (attempt >= maxAttempts || !retryable || isNonRetryablePostgrestError(err)) {
        throw err
      }
      const exp = Math.min(
        maxDelayMs,
        baseDelayMs * 2 ** (attempt - 1)
      )
      const jitter = Math.floor(Math.random() * Math.min(120, exp * 0.25))
      const delayMs = exp + jitter
      options?.onRetry?.({
        attempt,
        maxAttempts,
        delayMs,
        classification,
        code,
      })
      await sleep(delayMs, options?.signal)
    }
  }
  throw lastError
}

export type ReadTimeoutHandle = {
  signal: AbortSignal
  dispose: () => void
}

/** Per-attempt timeout; composes with an optional parent abort signal. */
export function createReadTimeoutSignal(
  timeoutMs: number,
  parent?: AbortSignal
): ReadTimeoutHandle {
  const controller = new AbortController()
  const timer = globalThis.setTimeout(() => {
    controller.abort(new DOMException("Read timed out", "TimeoutError"))
  }, timeoutMs)

  const onParentAbort = () => controller.abort(parent?.reason)
  parent?.addEventListener("abort", onParentAbort, { once: true })

  return {
    signal: controller.signal,
    dispose: () => {
      globalThis.clearTimeout(timer)
      parent?.removeEventListener("abort", onParentAbort)
    },
  }
}

export function supabaseResultToError(
  error: PostgrestLikeError | null,
  operation: string
): SupabaseReadError | null {
  if (!error) return null
  const classification = classifyServerReadError(error)
  return new SupabaseReadError(
    error.message ?? `${operation} failed`,
    classification === "unknown" ? "non_retryable" : classification,
    { code: error.code ?? null, cause: error }
  )
}
