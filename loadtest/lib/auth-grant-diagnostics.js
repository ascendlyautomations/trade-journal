/**
 * Sanitized Supabase password-grant failure details (k6 + shell preflight).
 * Never include passwords, access tokens, or refresh tokens in output.
 */

const REDACT_PATTERNS = [
  /access_token["']?\s*[:=]\s*["']?[^"'\s,}]+/gi,
  /refresh_token["']?\s*[:=]\s*["']?[^"'\s,}]+/gi,
  /password["']?\s*[:=]\s*["']?[^"'\s,}]+/gi,
  /Bearer\s+[A-Za-z0-9._-]+/gi,
]

export function maskPerfEmail(email) {
  const raw = String(email || "").trim()
  if (!raw || raw.indexOf("@") === -1) {
    return "(invalid-email)"
  }
  const parts = raw.split("@")
  const local = parts[0]
  const dom = parts.slice(1).join("@")
  if (local.length <= 2) {
    return "**@" + dom
  }
  return local.slice(0, 2) + "***@" + dom
}

export function redactSensitiveAuthText(text) {
  let out = String(text || "")
  for (let i = 0; i < REDACT_PATTERNS.length; i++) {
    out = out.replace(REDACT_PATTERNS[i], "[redacted]")
  }
  return out
}

export function parseAuthErrorBody(bodyText) {
  if (!bodyText || !String(bodyText).trim()) {
    return null
  }
  try {
    const obj = JSON.parse(bodyText)
    if (!obj || typeof obj !== "object") {
      return null
    }
    return obj
  } catch (_e) {
    return null
  }
}

/**
 * @returns {{ httpStatus: number, reason: string, detail: string }}
 */
export function describePasswordGrantFailure(httpStatus, bodyText) {
  const status = Number(httpStatus) || 0
  if (status === 0) {
    return {
      httpStatus: 0,
      reason: "client_timeout_or_network",
      detail: "HTTP 0 (k8s/k6: request timeout, connection reset, or DNS failure)",
    }
  }

  const parsed = parseAuthErrorBody(bodyText)
  if (parsed) {
    const code =
      parsed.error_code ||
      parsed.code ||
      parsed.error ||
      (parsed.msg ? "auth_error" : null)
    const msg =
      parsed.msg ||
      parsed.error_description ||
      parsed.message ||
      parsed.error ||
      ""
    const reason = code ? String(code) : "auth_http_" + status
    const detail = redactSensitiveAuthText(String(msg).slice(0, 240))
    return {
      httpStatus: status,
      reason: reason,
      detail: detail || "(empty auth error body)",
    }
  }

  const snippet = redactSensitiveAuthText(String(bodyText || "").slice(0, 240))
  return {
    httpStatus: status,
    reason: "auth_http_" + status,
    detail: snippet || "(non-JSON error body)",
  }
}

export function formatSetupAuthFailure(userIndex, email, failure, retryMeta) {
  const masked = maskPerfEmail(email)
  const f = failure || { httpStatus: 0, reason: "unknown", detail: "" }
  let msg =
    "Setup failed: authentication for test user index " +
    userIndex +
    " (" +
    masked +
    "): HTTP " +
    f.httpStatus +
    " " +
    f.reason +
    (f.detail ? " — " + f.detail : "")
  if (retryMeta && (retryMeta.grantAttempts > 1 || retryMeta.rateLimitRetries > 0)) {
    msg +=
      " [grant_attempts=" +
      retryMeta.grantAttempts +
      ", rate_limit_retries=" +
      retryMeta.rateLimitRetries +
      "]"
  }
  return msg
}
