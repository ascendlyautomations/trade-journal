/**
 * DEBUG-only Supabase REST/RPC request tracing.
 * Search browser console for `[DB_REQUEST]`.
 */

type DbRequestCacheState = "hit" | "miss" | "bypass" | "unknown"

type DbRequestLogOptions = {
  feature?: string
  operation: string
  key: string
  cache?: DbRequestCacheState
  deduped?: boolean
}

let installed = false
const inFlight = new Map<string, number>()
let requestSeq = 0

export function logDbRequest(options: DbRequestLogOptions): void {
  if (process.env.NODE_ENV !== "development") return
  const cache = options.cache ?? "unknown"
  const deduped = options.deduped === true
  const feature = options.feature ?? "unknown"
  console.log(
    `[DB_REQUEST] feature=${feature} operation=${options.operation} key=${options.key} cache=${cache} deduped=${deduped}`
  )
}

type DbWriteLogOptions = {
  feature?: string
  operation: "INSERT" | "UPDATE" | "DELETE" | "UPSERT" | "RPC"
  target: string
  reason?: string
  actionId?: string
}

export function logDbWrite(options: DbWriteLogOptions): void {
  if (process.env.NODE_ENV !== "development") return
  const feature = options.feature ?? "unknown"
  const reason = options.reason ?? "unknown"
  const actionId = options.actionId ?? "-"
  console.log(
    `[DB_WRITE] feature=${feature} operation=${options.operation} target=${options.target} reason=${reason} actionId=${actionId}`
  )
}

function parseRestOperation(url: URL): { operation: string; key: string } {
  const parts = url.pathname.split("/").filter(Boolean)
  const restIdx = parts.indexOf("rest")
  const segment = restIdx >= 0 ? parts[restIdx + 2] : parts.at(-1)
  if (segment === "rpc") {
    const rpcName = parts[restIdx + 3] ?? "unknown_rpc"
    return { operation: `rpc:${rpcName}`, key: rpcName }
  }
  const table = segment ?? "unknown_table"
  const filters = url.searchParams.get("conversation_id") ??
    url.searchParams.get("user_id") ??
    url.searchParams.get("id") ??
    url.searchParams.get("select")?.slice(0, 48) ??
    "list"
  return { operation: `table:${table}`, key: `${table}:${filters}` }
}

function shouldTraceUrl(url: URL): boolean {
  if (!url.pathname.includes("/rest/v1/")) return false
  if (url.pathname.includes("/auth/v1/")) return false
  return true
}

/** Install a global fetch wrapper once (client-only, development-only). */
export function installDbRequestDebugInterceptor(): void {
  if (typeof window === "undefined") return
  if (process.env.NODE_ENV !== "development") return
  if (installed) return
  installed = true

  const originalFetch = globalThis.fetch.bind(globalThis)
  globalThis.fetch = async (input, init) => {
    let url: URL | null = null
    try {
      url =
        typeof input === "string"
          ? new URL(input, window.location.origin)
          : input instanceof URL
            ? input
            : new URL(input.url, window.location.origin)
    } catch {
      return originalFetch(input, init)
    }

    if (!shouldTraceUrl(url)) {
      return originalFetch(input, init)
    }

    const method = (init?.method ?? "GET").toUpperCase()
    const { operation, key } = parseRestOperation(url)
    const dedupeKey = `${method}:${url.pathname}`
    const wasInFlight = inFlight.has(dedupeKey)
    const id = ++requestSeq
    inFlight.set(dedupeKey, id)

    if (method === "GET" || method === "HEAD") {
      logDbRequest({
        operation,
        key,
        cache: "unknown",
        deduped: wasInFlight,
      })
    } else {
      const writeOp =
        method === "POST" && url.pathname.includes("/rpc/")
          ? "RPC"
          : method === "POST"
            ? "INSERT"
            : method === "PATCH"
              ? "UPDATE"
              : method === "DELETE"
                ? "DELETE"
                : "UPSERT"
      logDbWrite({
        operation: writeOp,
        target: operation.replace(/^table:|^rpc:/, ""),
        reason: `http-${method.toLowerCase()}`,
      })
    }

    try {
      return await originalFetch(input, init)
    } finally {
      if (inFlight.get(dedupeKey) === id) {
        inFlight.delete(dedupeKey)
      }
    }
  }
}
