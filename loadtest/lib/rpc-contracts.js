/**
 * PostgREST RPC bodies — match lib/database.types.ts / Backend V2 repositories.
 */

import { FEED_PAGE_LIMIT } from "./constants.js"

export function feedBootstrapBody(options) {
  const o = options || {}
  const body = {
    p_scope: o.scope != null ? o.scope : "global",
    p_content_filter: o.contentFilter != null ? o.contentFilter : "all",
    p_limit: o.limit != null ? o.limit : FEED_PAGE_LIMIT,
  }
  if (o.cursor) {
    body.p_cursor = o.cursor
  }
  return JSON.stringify(body)
}

export function dashboardBootstrapBody(tradeLimit, accountId) {
  const body = { p_trade_limit: tradeLimit }
  if (accountId) {
    body.p_account_id = accountId
  }
  return JSON.stringify(body)
}

export function calendarBootstrapBody(year, month, accountId) {
  const body = { p_year: year, p_month: month }
  if (accountId) {
    body.p_account_id = accountId
  }
  return JSON.stringify(body)
}

export function tradesOwnerRowsBody(limit) {
  const body = {}
  if (limit != null) {
    body.p_limit = limit
  }
  return JSON.stringify(body)
}

export function currentUtcMonthYear() {
  const now = new Date()
  return { year: now.getUTCFullYear(), month: now.getUTCMonth() + 1 }
}
