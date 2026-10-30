import { uuidEquals } from "./k6-shared.js"

export function assertOwnSessionProfileRow(profiles, userId) {
  if (!Array.isArray(profiles) || profiles.length !== 1) {
    return false
  }
  const row = profiles[0]
  if (!row || typeof row !== "object") {
    return false
  }
  if (!uuidEquals(row.id, userId)) {
    return false
  }
  const keys = ["id", "name", "username", "onboarding_completed", "is_pro", "avatar_url"]
  for (let i = 0; i < keys.length; i++) {
    if (!Object.prototype.hasOwnProperty.call(row, keys[i])) {
      return false
    }
  }
  return true
}

export function assertBootstrapMeta(meta, userId) {
  if (!meta || typeof meta !== "object" || Array.isArray(meta)) {
    return false
  }
  if (meta.contract_version !== "v1") {
    return false
  }
  if (userId && !uuidEquals(meta.viewer_id, userId)) {
    return false
  }
  return true
}

export function assertDashboardBootstrap(body, userId) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return false
  }
  if (!assertBootstrapMeta(body.meta, userId)) {
    return false
  }
  const data = body.data
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return false
  }
  if (!Array.isArray(data.accounts) || !Array.isArray(data.trade_window)) {
    return false
  }
  if (!data.trade_window_meta || typeof data.trade_window_meta !== "object" || Array.isArray(data.trade_window_meta)) {
    return false
  }
  return true
}

export function assertFeedBootstrap(body, userId) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return false
  }
  if (!assertBootstrapMeta(body.meta, userId)) {
    return false
  }
  const data = body.data
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return false
  }
  if (!Array.isArray(data.items)) {
    return false
  }
  return true
}

export function assertCalendarBootstrap(body, userId) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return false
  }
  if (!assertBootstrapMeta(body.meta, userId)) {
    return false
  }
  const data = body.data
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return false
  }
  if (typeof data.year !== "number" || typeof data.month !== "number") {
    return false
  }
  if (!Array.isArray(data.accounts)) {
    return false
  }
  if (!data.metrics_month || typeof data.metrics_month !== "object" || Array.isArray(data.metrics_month)) {
    return false
  }
  if (!Array.isArray(data.trades) && !data.trades_by_day) {
    return false
  }
  if (data.trades != null && !Array.isArray(data.trades)) {
    return false
  }
  return true
}

export function assertOwnerTradeRows(body) {
  if (!Array.isArray(body)) {
    return false
  }
  for (let i = 0; i < body.length; i++) {
    const row = body[i]
    if (!row || typeof row !== "object" || !row.id) {
      return false
    }
  }
  return true
}
