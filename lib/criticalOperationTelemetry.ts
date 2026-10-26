/**
 * Production observability for high-impact failures (Sentry when configured).
 * Never attach tokens, passwords, or full trade payloads.
 */

type CriticalOperationContext = Record<string, string | number | boolean | null | undefined>

const recentFingerprints = new Map<string, number>()
const DEDUPE_MS = 60_000

function fingerprint(operation: string, context: CriticalOperationContext): string {
  const parts = Object.keys(context)
    .sort()
    .map((k) => `${k}=${String(context[k] ?? "")}`)
  return `${operation}|${parts.join("|")}`
}

function shouldReport(fp: string): boolean {
  const now = Date.now()
  const last = recentFingerprints.get(fp)
  if (last != null && now - last < DEDUPE_MS) return false
  recentFingerprints.set(fp, now)
  return true
}

export function reportCriticalOperationFailure(params: {
  operation: string
  error: unknown
  context?: CriticalOperationContext
}): void {
  const message =
    params.error instanceof Error
      ? params.error.message
      : String(params.error ?? "unknown error")
  const ctx = params.context ?? {}
  console.error(`[critical:${params.operation}]`, message, ctx)

  const fp = fingerprint(params.operation, {
    ...ctx,
    message: message.slice(0, 200),
  })
  if (!shouldReport(fp)) return

  if (typeof window === "undefined") {
    void import("@sentry/nextjs")
      .then((Sentry) => {
        Sentry.captureException(
          params.error instanceof Error ? params.error : new Error(message),
          {
            tags: { critical_operation: params.operation },
            extra: ctx,
          }
        )
      })
      .catch(() => {})
    return
  }

  void import("@sentry/nextjs")
    .then((Sentry) => {
      Sentry.captureException(
        params.error instanceof Error ? params.error : new Error(message),
        {
          tags: { critical_operation: params.operation },
          extra: ctx,
        }
      )
    })
    .catch(() => {})
}
