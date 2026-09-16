const SENSITIVE_KEYS = new Set([
  "password",
  "credentials",
  "credentials_ciphertext",
  "credentialsCiphertext",
])

export function assertRithmicConnectResponseSafe(value: unknown): void {
  walk(value, "")
}

function walk(node: unknown, path: string): void {
  if (node === null || node === undefined) return
  if (typeof node === "string") {
    if (path.endsWith("password") || path.includes(".password")) {
      throw new Error("rithmic_connect_response_leaked_password")
    }
    return
  }
  if (Array.isArray(node)) {
    for (const item of node) walk(item, path)
    return
  }
  if (typeof node === "object") {
    for (const [key, val] of Object.entries(node as Record<string, unknown>)) {
      if (SENSITIVE_KEYS.has(key)) {
        throw new Error(`rithmic_connect_response_leaked_${key}`)
      }
      walk(val, path ? `${path}.${key}` : key)
    }
  }
}

export function sanitizeConnectRequestBody(body: unknown): {
  username: string
  password: string
  systemName: string | null
  reconnectConnectionId: string | null
} | null {
  if (!body || typeof body !== "object") return null
  const o = body as Record<string, unknown>
  const username = typeof o.username === "string" ? o.username.trim() : ""
  const password = typeof o.password === "string" ? o.password : ""
  if (!username || !password) return null
  const systemName =
    typeof o.systemName === "string" && o.systemName.trim()
      ? o.systemName.trim()
      : null
  const reconnectConnectionId =
    typeof o.reconnectConnectionId === "string" && o.reconnectConnectionId.trim()
      ? o.reconnectConnectionId.trim()
      : null
  return { username, password, systemName, reconnectConnectionId }
}

export function sanitizeRithmicSyncRequestBody(body: unknown): {
  password: string
} | null {
  if (!body || typeof body !== "object") return null
  const o = body as Record<string, unknown>
  const password = typeof o.password === "string" ? o.password : ""
  if (!password) return null
  return { password }
}
