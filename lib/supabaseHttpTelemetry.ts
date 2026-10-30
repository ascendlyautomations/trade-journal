/**
 * Sanitize Supabase HTTP span data and copy safe gateway headers onto the
 * active Sentry span. Never attach Authorization, API keys, or raw row ids.
 */

const UUID_RE =
  /[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/gi
const JWT_RE = /eyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}/g
const EMAIL_RE = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g

const KEEP_QUERY_KEYS = new Set(["select", "limit", "offset", "order", "on_conflict"])

const SENSITIVE_SPAN_KEY =
  /(authorization|set-cookie|(^|[./_-])cookie$|(^|[./_-])apikey$|api-key|access[_-]?token|refresh[_-]?token|x-api-key)/i

export type SentrySpanLike = {
  op?: string
  description?: string
  data?: Record<string, unknown>
}

export function isSupabaseRequestUrl(raw: string): boolean {
  try {
    const url = new URL(raw)
    return (
      url.hostname.endsWith(".supabase.co") ||
      url.hostname.endsWith(".supabase.in")
    )
  } catch {
    return false
  }
}

function redactSecrets(value: string): string {
  return value
    .replace(JWT_RE, "<jwt>")
    .replace(UUID_RE, "<id>")
    .replace(EMAIL_RE, "<email>")
}

function redactPostgrestFilterValue(value: string): string {
  const cleaned = redactSecrets(value)
  const dot = cleaned.indexOf(".")
  if (dot <= 0) return "<redacted>"
  const op = cleaned.slice(0, dot)
  if (!/^[a-z*]+$/i.test(op)) return "<redacted>"
  const rest = cleaned.slice(dot + 1)
  if (op === "in" || op === "cs" || op === "cd" || op === "ov") {
    return `${op}.<ids>`
  }
  if (
    rest === "<id>" ||
    rest === "<jwt>" ||
    rest === "<email>" ||
    rest.includes("<id>") ||
    rest.includes("<jwt>")
  ) {
    return `${op}.${rest.includes("<id>") ? "<id>" : rest}`
  }
  if (/^(true|false|null|-?\d+(?:\.\d+)?)$/i.test(rest)) return `${op}.${rest}`
  if (/^\d{4}-\d{2}-\d{2}/.test(rest)) return `${op}.${rest}`
  if (rest === "*" || rest === "") return `${op}.${rest || "<redacted>"}`
  return `${op}.<redacted>`
}

/** Query fingerprint safe to store on a Sentry span. */
export function supabaseQueryFingerprint(
  searchParams: URLSearchParams,
  pathname: string
): string {
  if (pathname.startsWith("/auth/")) return ""
  const parts: string[] = []
  for (const [key, rawValue] of searchParams.entries()) {
    const lower = key.toLowerCase()
    if (lower === "apikey" || lower === "access_token" || lower === "refresh_token") {
      continue
    }
    if (KEEP_QUERY_KEYS.has(lower)) {
      const kept = redactSecrets(rawValue)
      parts.push(`${key}=${kept.length > 280 ? `${kept.slice(0, 280)}…` : kept}`)
      continue
    }
    parts.push(`${key}=${redactPostgrestFilterValue(rawValue)}`)
  }
  return parts.join("&")
}

export function sanitizeSupabaseUrl(raw: string): string {
  try {
    const url = new URL(raw)
    if (
      !url.hostname.endsWith(".supabase.co") &&
      !url.hostname.endsWith(".supabase.in")
    ) {
      return raw
    }
    const fingerprint = supabaseQueryFingerprint(url.searchParams, url.pathname)
    url.search = fingerprint ? `?${fingerprint}` : ""
    url.hash = ""
    url.username = ""
    url.password = ""
    return url.toString()
  } catch {
    return raw
  }
}

export function supabaseSpanAttributesFromResponse(
  rawUrl: string,
  headers: Pick<Headers, "get">
): Record<string, string | number> {
  const attrs: Record<string, string | number> = {}
  try {
    const url = new URL(rawUrl)
    attrs["url.path"] = url.pathname
    const fingerprint = supabaseQueryFingerprint(url.searchParams, url.pathname)
    if (fingerprint) attrs["http.query"] = fingerprint
    const rpcName = url.pathname.match(/\/rest\/v1\/rpc\/([^/]+)/)?.[1]
    if (rpcName) attrs["supabase.rpc"] = rpcName
  } catch {
    // ignore malformed URLs
  }

  const upstream = headers.get("x-envoy-upstream-service-time")
  if (upstream && /^\d+$/.test(upstream)) {
    attrs["supabase.upstream_ms"] = Number(upstream)
  } else if (upstream) {
    attrs["supabase.upstream_ms"] = upstream
  }
  const cfRay = headers.get("cf-ray")
  if (cfRay) attrs["supabase.cf_ray"] = cfRay
  const contentRange = headers.get("content-range")
  if (contentRange) attrs["supabase.content_range"] = contentRange
  return attrs
}

function sanitizeSpanUrlField(
  data: Record<string, unknown>,
  key: string
): void {
  const value = data[key]
  if (typeof value !== "string" || !isSupabaseRequestUrl(value)) return
  data[key] = sanitizeSupabaseUrl(value)
}

/** Drop secrets and replace full query strings on Supabase http.client spans. */
export function sanitizeSentrySpanForSupabase<T extends SentrySpanLike>(
  span: T
): T {
  const description = span.description
  if (typeof description === "string") {
    const urlStart = description.search(/https?:\/\//i)
    if (urlStart >= 0) {
      const maybeUrl = description.slice(urlStart)
      if (isSupabaseRequestUrl(maybeUrl.split(" ")[0] ?? maybeUrl)) {
        span.description =
          description.slice(0, urlStart) + sanitizeSupabaseUrl(maybeUrl.split(" ")[0] ?? maybeUrl)
      }
    }
  }

  const data = span.data
  if (!data || typeof data !== "object") return span

  for (const key of Object.keys(data)) {
    if (SENSITIVE_SPAN_KEY.test(key)) {
      delete data[key]
    }
  }

  sanitizeSpanUrlField(data, "http.url")
  sanitizeSpanUrlField(data, "url.full")
  sanitizeSpanUrlField(data, "url")

  const query = data["http.query"]
  if (typeof query === "string") {
    try {
      const full =
        typeof data["url.full"] === "string"
          ? data["url.full"]
          : typeof data["http.url"] === "string"
            ? data["http.url"]
            : null
      const pathname = full ? new URL(full).pathname : "/rest/v1/"
      data["http.query"] = supabaseQueryFingerprint(
        new URLSearchParams(query.startsWith("?") ? query.slice(1) : query),
        pathname
      )
    } catch {
      data["http.query"] = "<redacted>"
    }
  }

  return span
}

function requestUrlFromInput(input: RequestInfo | URL): string | null {
  if (typeof input === "string") return input
  if (input instanceof URL) return input.toString()
  if (typeof Request !== "undefined" && input instanceof Request) return input.url
  return null
}

async function annotateActiveSpan(
  rawUrl: string,
  response: Response
): Promise<void> {
  if (!isSupabaseRequestUrl(rawUrl)) return
  const Sentry = await import("@sentry/nextjs")
  const span = Sentry.getActiveSpan?.()
  if (!span || typeof span.setAttribute !== "function") return
  const attrs = supabaseSpanAttributesFromResponse(rawUrl, response.headers)
  for (const [key, value] of Object.entries(attrs)) {
    span.setAttribute(key, value)
  }
  span.setAttribute("http.url", sanitizeSupabaseUrl(rawUrl))
}

/** Custom supabase-js fetch: records safe gateway headers on the active span. */
export async function instrumentedSupabaseFetch(
  input: RequestInfo | URL,
  init?: RequestInit
): Promise<Response> {
  const response = await globalThis.fetch(input, init)
  const rawUrl = requestUrlFromInput(input)
  if (rawUrl) {
    try {
      await annotateActiveSpan(rawUrl, response)
    } catch {
      // Telemetry must never fail the query.
    }
  }
  return response
}
