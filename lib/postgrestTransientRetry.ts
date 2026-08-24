/**
 * Transient PostgREST / schema-cache errors (e.g. PGRST002).
 * One bounded retry with jitter — not a poll loop.
 */

export type PostgrestLikeError = {
  code?: string | null
  message?: string | null
}

export function isTransientPostgrestError(error: unknown): boolean {
  if (!error || typeof error !== "object") return false
  const e = error as PostgrestLikeError
  const code = String(e.code ?? "").toUpperCase()
  const msg = String(e.message ?? "").toLowerCase()
  if (code === "PGRST002" || code === "PGRST003") return true
  if (msg.includes("schema cache") && msg.includes("retry")) return true
  if (msg.includes("could not query the database for the schema cache")) {
    return true
  }
  return false
}

export function isNonRetryablePostgrestError(error: unknown): boolean {
  if (!error || typeof error !== "object") return false
  const e = error as PostgrestLikeError
  const code = String(e.code ?? "").toUpperCase()
  if (code === "PGRST202" || code === "42883") return true
  if (code === "401" || code === "403" || code === "42501") return true
  const msg = String(e.message ?? "").toLowerCase()
  if (msg.includes("could not find the function")) return true
  if (msg.includes("jwt")) return true
  return false
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

export type TransientRetryMeta = {
  attempts: number
  retried: boolean
  lastCode: string | null
}

/** At most one automatic retry (2 attempts total) for idempotent reads. */
export async function withTransientPostgrestRetry<T>(
  fn: (attempt: number) => Promise<T>,
  options?: {
    signal?: AbortSignal
    baseDelayMs?: number
    onRetry?: (meta: TransientRetryMeta) => void
  }
): Promise<T> {
  const baseDelayMs = options?.baseDelayMs ?? 120
  let lastError: unknown
  for (let attempt = 1; attempt <= 2; attempt++) {
    if (options?.signal?.aborted) {
      throw new DOMException("Aborted", "AbortError")
    }
    try {
      return await fn(attempt)
    } catch (err) {
      lastError = err
      const code =
        err && typeof err === "object" && "code" in err
          ? String((err as PostgrestLikeError).code ?? "")
          : null
      if (
        attempt >= 2 ||
        isNonRetryablePostgrestError(err) ||
        !isTransientPostgrestError(err)
      ) {
        throw err
      }
      const jitter = Math.floor(Math.random() * 80)
      options?.onRetry?.({
        attempts: attempt,
        retried: true,
        lastCode: code,
      })
      await sleep(baseDelayMs + jitter, options?.signal)
    }
  }
  throw lastError
}
