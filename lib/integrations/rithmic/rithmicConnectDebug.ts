/** Opt-in connect diagnostics (no credentials). Set `RITHMIC_CONNECT_DEBUG=1`. */
export function isRithmicConnectDebugEnabled(): boolean {
  return process.env.RITHMIC_CONNECT_DEBUG === "1"
}

export type RithmicConnectDebugPayload = Record<
  string,
  string | number | boolean | string[] | null
>

const BLOCKED_KEYS = new Set(["password", "user", "username", "token", "credential"])

export function logRithmicConnectDebug(
  stage: string,
  details: RithmicConnectDebugPayload
): void {
  if (!isRithmicConnectDebugEnabled()) return

  const safe: Record<string, string | number | boolean | string[]> = { stage }
  for (const [key, val] of Object.entries(details)) {
    if (val === undefined || val === null) continue
    const lower = key.toLowerCase()
    if (BLOCKED_KEYS.has(lower) || lower.includes("password") || lower.includes("token")) {
      continue
    }
    if (Array.isArray(val)) {
      safe[key] = val.map((v) => String(v).slice(0, 120))
      continue
    }
    if (typeof val === "string") {
      safe[key] = val.slice(0, 500)
      continue
    }
    safe[key] = val
  }
  console.info("[rithmic/connect/debug]", JSON.stringify(safe))
}