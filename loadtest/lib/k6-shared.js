/**
 * Shared k6 helpers (goja-safe — no URL global, explicit response bodies when discarding).
 */

export function trimEnvValue(value) {
  let s = String(value).trim()
  if (
    (s.charAt(0) === '"' && s.charAt(s.length - 1) === '"') ||
    (s.charAt(0) === "'" && s.charAt(s.length - 1) === "'")
  ) {
    s = s.slice(1, -1).trim()
  }
  return s
}

export function requiredEnv(name) {
  const value = __ENV[name]
  if (!value || !String(value).trim()) {
    throw new Error("Missing " + name)
  }
  return trimEnvValue(value)
}

/** k6/goja has no global URL. */
export function parseHttpsUrl(raw) {
  const value = trimEnvValue(raw)
  const match = /^https:\/\/([a-z0-9.-]+)(?::\d+)?(?:\/.*)?$/i.exec(value)
  if (!match) {
    return null
  }
  return {
    protocol: "https:",
    hostname: match[1].toLowerCase(),
    href: value.replace(/\/+$/, ""),
  }
}

export function requiredHttpsUrl(name) {
  const value = requiredEnv(name)
  const parsed = parseHttpsUrl(value)
  if (!parsed) {
    throw new Error(name + " is not a URL")
  }
  return parsed.href
}

export function supabaseHeaders(anonKey, token, extra) {
  const base = {
    apikey: anonKey,
    Authorization: "Bearer " + token,
    Accept: "application/json",
  }
  if (!extra) {
    return base
  }
  for (const key in extra) {
    base[key] = extra[key]
  }
  return base
}

/** Use responseType "text" whenever JSON is parsed and discardResponseBodies is true. */
export function httpParams(pageTag, options) {
  const tags = { page: pageTag }
  if (options && options.extraTags) {
    for (const key in options.extraTags) {
      tags[key] = options.extraTags[key]
    }
  }
  const params = {
    responseType: options && options.parseBody ? "text" : "none",
    timeout: options && options.timeout ? options.timeout : "8s",
    tags: tags,
  }
  if (options && options.responseType) {
    params.responseType = options.responseType
  }
  return params
}

export function parseJsonBody(res, label) {
  if (res.body == null || res.body === "") {
    throw new Error(
      label + ": response body missing (set responseType text when discardResponseBodies is enabled)"
    )
  }
  try {
    return JSON.parse(res.body)
  } catch (error) {
    throw new Error(label + ": invalid JSON — " + sanitizeErrorSnippet(res.body))
  }
}

/** PostgREST / Supabase error payload — no secrets. */
export function sanitizeErrorSnippet(body) {
  if (body == null) {
    return "(empty body)"
  }
  const text = String(body).slice(0, 280)
  try {
    const j = JSON.parse(body)
    const parts = []
    if (j.code) parts.push("code=" + j.code)
    if (j.message) parts.push(String(j.message).slice(0, 160))
    if (j.hint) parts.push("hint=" + String(j.hint).slice(0, 80))
    return parts.length ? parts.join(" ") : text
  } catch (e) {
    return text
  }
}

export function classifyHttpFailure(status, body) {
  const snippet = sanitizeErrorSnippet(body)
  if (status === 401) {
    return { kind: "auth", detail: snippet }
  }
  if (status === 403) {
    return { kind: "forbidden", detail: snippet }
  }
  if (status === 404 && snippet.indexOf("PGRST202") !== -1) {
    return { kind: "rpc_signature", detail: snippet }
  }
  if (status >= 500) {
    return { kind: "server", detail: snippet }
  }
  if (status >= 400) {
    return { kind: "client", detail: snippet }
  }
  return { kind: "unknown", detail: snippet }
}

export function assertHttpOk(res, label, requireStatus, outcomeKind) {
  if (typeof __recordHttpOutcome === "function") {
    __recordHttpOutcome(res, outcomeKind || label, label)
  }
  const expected = requireStatus != null ? requireStatus : 200
  const ok =
    requireStatus != null
      ? res.status === expected
      : res.status >= 200 && res.status < 300
  if (ok) {
    return true
  }
  const kind = classifyHttpFailure(res.status, res.body)
  throw new Error(
    label +
      " failed (" +
      kind.kind +
      " HTTP " +
      res.status +
      "): " +
      kind.detail
  )
}

export function encodeUserId(userId) {
  return encodeURIComponent(userId)
}

export function uuidEquals(a, b) {
  return String(a || "").toLowerCase() === String(b || "").toLowerCase()
}
