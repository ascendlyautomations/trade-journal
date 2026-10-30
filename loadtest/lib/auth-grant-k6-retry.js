/**
 * Bounded 429 backoff for k6 password grants (setup + refresh).
 * Honors Retry-After when present; never logs credentials.
 */

import { sleep } from "k6"

export const SETUP_AUTH_MAX_RETRIES = 12
/** Max wait between 429 retries (seconds). */
export const SETUP_AUTH_BACKOFF_CAP_SEC = 60

export function parseRetryAfterMs(res) {
  if (!res || !res.headers) {
    return null
  }
  const raw = res.headers["Retry-After"] || res.headers["retry-after"]
  if (raw == null || raw === "") {
    return null
  }
  const asNum = Number(raw)
  if (Number.isFinite(asNum) && asNum >= 0) {
    return asNum * 1000
  }
  const asDate = Date.parse(String(raw))
  if (!Number.isNaN(asDate)) {
    return Math.max(0, asDate - Date.now())
  }
  return null
}

export function authBackoffMs(attempt, retryAfterMs) {
  if (retryAfterMs != null) {
    return Math.min(SETUP_AUTH_BACKOFF_CAP_SEC * 1000, retryAfterMs + Math.floor(Math.random() * 250))
  }
  const base = Math.min(SETUP_AUTH_BACKOFF_CAP_SEC * 1000, 800 * Math.pow(2, attempt))
  return base + Math.floor(Math.random() * base * 0.25)
}

export function sleepMs(ms) {
  sleep(ms / 1000)
}
