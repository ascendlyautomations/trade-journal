/**
 * Production read-only API workload — shared by k6 preflight (setup) and VU scenarios.
 */

import http from "k6/http"
import { sleep } from "k6"
import exec from "k6/execution"
import {
  ACCOUNTS_SELECT,
  DASHBOARD_OWNER_ROWS_HISTORY,
  DASHBOARD_OWNER_ROWS_WINDOW,
  DASHBOARD_RPC_TRADE_LIMIT,
  FEED_PAGE_LIMIT,
  PREFLIGHT_DASHBOARD_TRADE_LIMIT,
  PREFLIGHT_OWNER_ROWS_LIMIT,
  PROFILE_PUBLIC_TRADES_SELECT,
  PUBLIC_PROFILE_SELECT,
  RPC_NAMES,
  SESSION_PROFILE_SELECT,
  TRADES_PAGE_OWNER_ROWS_LIMIT,
} from "./constants.js"
import { describePasswordGrantFailure } from "./auth-grant-diagnostics.js"
import {
  authBackoffMs,
  parseRetryAfterMs,
  SETUP_AUTH_MAX_RETRIES,
  sleepMs,
} from "./auth-grant-k6-retry.js"
import { recordHttpOutcome } from "./k6-diagnostics.js"
import {
  assertHttpOk,
  encodeUserId,
  httpParams,
  parseJsonBody,
  supabaseHeaders,
} from "./k6-shared.js"
import {
  calendarBootstrapBody,
  currentUtcMonthYear,
  dashboardBootstrapBody,
  feedBootstrapBody,
  tradesOwnerRowsBody,
} from "./rpc-contracts.js"
import {
  assertCalendarBootstrap,
  assertDashboardBootstrap,
  assertFeedBootstrap,
  assertOwnSessionProfileRow,
  assertOwnerTradeRows,
} from "./validators.js"

function restUrl(base, path) {
  return base + "/rest/v1/" + path
}

function rpcUrl(base, name) {
  return base + "/rest/v1/rpc/" + name
}

function jsonPost(base, anonKey, token, rpcName, body, pageTag, parseBody, extraTags) {
  return http.post(rpcUrl(base, rpcName), body, {
    headers: supabaseHeaders(anonKey, token, { "Content-Type": "application/json" }),
    ...httpParams(pageTag, {
      parseBody: parseBody,
      responseType: parseBody ? "text" : "none",
      extraTags: extraTags,
    }),
  })
}

function feedExtraTags(cursor) {
  return {
    rpc: RPC_NAMES.feed,
    feed_cursor: cursor ? "next" : "first",
  }
}

function jsonGet(base, anonKey, token, path, pageTag, parseBody) {
  return http.get(restUrl(base, path), {
    headers: supabaseHeaders(anonKey, token),
    ...httpParams(pageTag, { parseBody: parseBody }),
  })
}

function passwordGrantHttpOnce(base, anonKey, user, pageTag) {
  return http.post(
    base + "/auth/v1/token?grant_type=password",
    JSON.stringify({ email: user.email, password: user.password }),
    {
      headers: { apikey: anonKey, "Content-Type": "application/json" },
      tags: { page: pageTag },
      responseType: "text",
      timeout: "8s",
    }
  )
}

function sessionFromPasswordGrantResponse(res, user) {
  if (res.status !== 200) {
    return {
      session: null,
      failure: describePasswordGrantFailure(res.status, res.body),
    }
  }
  const body = parseJsonBody(res, "auth")
  if (!body.access_token || !body.user || !body.user.id) {
    return {
      session: null,
      failure: describePasswordGrantFailure(
        res.status,
        JSON.stringify({ msg: "missing access_token or user.id in 200 response" })
      ),
    }
  }
  return {
    session: {
      email: user.email,
      userId: body.user.id,
      token: body.access_token,
    },
    failure: null,
  }
}

export function loginPasswordGrantDetailed(base, anonKey, user, pageTag) {
  const res = passwordGrantHttpOnce(base, anonKey, user, pageTag)
  recordHttpOutcome(res, "auth", pageTag)
  return sessionFromPasswordGrantResponse(res, user)
}

/**
 * Setup-time password grant with bounded 429 backoff (Retry-After + exponential jitter).
 */
export function loginPasswordGrantDetailedWithRetry(base, anonKey, user, pageTag) {
  let grantAttempts = 0
  let rateLimitRetries = 0
  let lastFailure = null

  while (true) {
    grantAttempts += 1
    const res = passwordGrantHttpOnce(base, anonKey, user, pageTag)
    recordHttpOutcome(res, "auth", pageTag)
    const parsed = sessionFromPasswordGrantResponse(res, user)
    if (parsed.session) {
      return {
        session: parsed.session,
        failure: null,
        retryMeta: { grantAttempts: grantAttempts, rateLimitRetries: rateLimitRetries },
      }
    }
    lastFailure = parsed.failure
    const status = lastFailure && lastFailure.httpStatus
    if (status === 429 && rateLimitRetries < SETUP_AUTH_MAX_RETRIES) {
      rateLimitRetries += 1
      const waitMs = authBackoffMs(rateLimitRetries, parseRetryAfterMs(res))
      sleepMs(waitMs)
      continue
    }
    return {
      session: null,
      failure: lastFailure,
      retryMeta: { grantAttempts: grantAttempts, rateLimitRetries: rateLimitRetries },
    }
  }
}

export function loginPasswordGrant(base, anonKey, user, pageTag) {
  return loginPasswordGrantDetailed(base, anonKey, user, pageTag).session
}

export function readSessionProfile(base, anonKey, session, pageTag, validate) {
  const id = encodeUserId(session.userId)
  const res = jsonGet(
    base,
    anonKey,
    session.token,
    "profiles?id=eq." + id + "&select=" + SESSION_PROFILE_SELECT,
    pageTag,
    validate
  )
  assertHttpOk(res, pageTag)
  if (!validate) {
    return null
  }
  const rows = parseJsonBody(res, pageTag)
  if (!assertOwnSessionProfileRow(rows, session.userId)) {
    throw new Error(pageTag + ": profile data shape")
  }
  return rows
}

export function readAccounts(base, anonKey, session, pageTag, validate) {
  const id = encodeUserId(session.userId)
  const res = jsonGet(
    base,
    anonKey,
    session.token,
    "accounts?user_id=eq." + id + "&select=" + ACCOUNTS_SELECT,
    pageTag,
    validate
  )
  assertHttpOk(res, pageTag)
  if (!validate) {
    return null
  }
  const rows = parseJsonBody(res, pageTag)
  if (!Array.isArray(rows)) {
    throw new Error(pageTag + ": accounts data shape")
  }
  return rows
}

export function readOwnerTradeRows(base, anonKey, session, pageTag, limit, validate) {
  const res = jsonPost(
    base,
    anonKey,
    session.token,
    RPC_NAMES.tradesOwnerRows,
    tradesOwnerRowsBody(limit),
    pageTag,
    validate
  )
  assertHttpOk(res, pageTag)
  if (!validate) {
    return null
  }
  const rows = parseJsonBody(res, pageTag)
  if (!assertOwnerTradeRows(rows)) {
    throw new Error(pageTag + ": owner trade rows shape")
  }
  return rows
}

export function readFeedBootstrap(base, anonKey, session, pageTag, cursor, validate, feedScope) {
  const res = jsonPost(
    base,
    anonKey,
    session.token,
    RPC_NAMES.feed,
    feedBootstrapBody({ limit: FEED_PAGE_LIMIT, cursor: cursor, scope: feedScope }),
    pageTag,
    validate,
    feedExtraTags(cursor)
  )
  assertHttpOk(res, pageTag, 200, RPC_NAMES.feed)
  if (!validate) {
    return null
  }
  const body = parseJsonBody(res, pageTag)
  if (!assertFeedBootstrap(body, session.userId)) {
    throw new Error(pageTag + ": feed data shape")
  }
  return body
}

export function readDashboardBootstrap(base, anonKey, session, pageTag, tradeLimit, validate) {
  const res = jsonPost(
    base,
    anonKey,
    session.token,
    RPC_NAMES.dashboard,
    dashboardBootstrapBody(tradeLimit),
    pageTag,
    validate
  )
  assertHttpOk(res, pageTag, 200)
  if (!validate) {
    return null
  }
  const body = parseJsonBody(res, pageTag)
  if (!assertDashboardBootstrap(body, session.userId)) {
    throw new Error(pageTag + ": dashboard RPC data shape")
  }
  return body
}

export function readCalendarBootstrap(base, anonKey, session, pageTag, validate) {
  const ym = currentUtcMonthYear()
  const res = jsonPost(
    base,
    anonKey,
    session.token,
    RPC_NAMES.calendar,
    calendarBootstrapBody(ym.year, ym.month),
    pageTag,
    validate
  )
  assertHttpOk(res, pageTag, 200)
  if (!validate) {
    return null
  }
  const body = parseJsonBody(res, pageTag)
  if (!assertCalendarBootstrap(body, session.userId)) {
    throw new Error(pageTag + ": calendar RPC data shape")
  }
  return body
}

export function readPublicProfile(base, anonKey, session, pageTag) {
  const id = encodeUserId(session.userId)
  const res = jsonGet(
    base,
    anonKey,
    session.token,
    "profiles?id=eq." + id + "&select=" + PUBLIC_PROFILE_SELECT,
    pageTag,
    false
  )
  assertHttpOk(res, pageTag)
}

export function readProfileFollowerCounts(base, anonKey, session, pageTag) {
  const id = encodeUserId(session.userId)
  const countHeaders = supabaseHeaders(anonKey, session.token, { Prefer: "count=exact" })
  http.head(restUrl(base, "followers?following_id=eq." + id + "&select=*"), {
    headers: countHeaders,
    tags: { page: pageTag },
    timeout: "8s",
  })
  http.head(restUrl(base, "followers?follower_id=eq." + id + "&select=*"), {
    headers: countHeaders,
    tags: { page: pageTag },
    timeout: "8s",
  })
}

export function readProfilePublicTrades(base, anonKey, session, pageTag) {
  const id = encodeUserId(session.userId)
  const res = jsonGet(
    base,
    anonKey,
    session.token,
    "trades?user_id=eq." +
      id +
      "&select=" +
      PROFILE_PUBLIC_TRADES_SELECT +
      "&is_public=eq.true&order=created_at.desc&limit=6",
    pageTag,
    false
  )
  assertHttpOk(res, pageTag)
}

/** Full preflight — throws with classified errors on failure. */
export function runProductionReadPreflight(base, anonKey, session) {
  readSessionProfile(base, anonKey, session, "preflight_profile", true)
  readAccounts(base, anonKey, session, "preflight_accounts", true)
  readOwnerTradeRows(base, anonKey, session, "preflight_trades", PREFLIGHT_OWNER_ROWS_LIMIT, true)
  readFeedBootstrap(base, anonKey, session, "preflight_feed", null, true)
  readDashboardBootstrap(base, anonKey, session, "preflight_dashboard_rpc", PREFLIGHT_DASHBOARD_TRADE_LIMIT, true)
  readCalendarBootstrap(base, anonKey, session, "preflight_calendar", true)
}

export function scenarioDashboard(base, anonKey, session, paceShort) {
  readSessionProfile(base, anonKey, session, "dashboard_profile", false)
  readAccounts(base, anonKey, session, "dashboard_accounts", false)
  readOwnerTradeRows(base, anonKey, session, "dashboard_window", DASHBOARD_OWNER_ROWS_WINDOW, false)
  if (paceShort) {
    paceShort()
  }
  readOwnerTradeRows(base, anonKey, session, "dashboard_history", DASHBOARD_OWNER_ROWS_HISTORY, false)
}

export function scenarioDashboardRpc(base, anonKey, session) {
  const res = jsonPost(
    base,
    anonKey,
    session.token,
    RPC_NAMES.dashboard,
    dashboardBootstrapBody(DASHBOARD_RPC_TRADE_LIMIT),
    "dashboard_rpc",
    false
  )
  assertHttpOk(res, "dashboard_rpc", 200)
}

export function scenarioTrades(base, anonKey, session) {
  readOwnerTradeRows(base, anonKey, session, "trades", TRADES_PAGE_OWNER_ROWS_LIMIT, false)
}

export function scenarioCalendar(base, anonKey, session) {
  readAccounts(base, anonKey, session, "calendar_accounts", false)
  readCalendarBootstrap(base, anonKey, session, "calendar", false)
}

export function scenarioProfile(base, anonKey, session) {
  readPublicProfile(base, anonKey, session, "profile")
  readProfileFollowerCounts(base, anonKey, session, "profile")
  readProfilePublicTrades(base, anonKey, session, "profile_trades")
}

/** Direct stress default: global first page (heaviest PostgREST path). */
export function scenarioFeed(base, anonKey, session, withPagination) {
  scenarioFeedWithOptions(base, anonKey, session, {
    scope: "global",
    withPagination: withPagination,
  })
}

export function scenarioFeedWithOptions(base, anonKey, session, options) {
  const o = options || {}
  const scope = o.scope != null ? o.scope : "following"
  const withPagination = o.withPagination === true
  if (!withPagination) {
    const res = jsonPost(
      base,
      anonKey,
      session.token,
      RPC_NAMES.feed,
      feedBootstrapBody({ limit: FEED_PAGE_LIMIT, scope: scope }),
      "feed",
      false,
      feedExtraTags(null)
    )
    assertHttpOk(res, "feed", 200, RPC_NAMES.feed)
    return
  }
  const body = readFeedBootstrap(base, anonKey, session, "feed", null, true, scope)
  const cursor = body && body.data ? body.data.next_cursor : null
  if (!cursor) {
    return
  }
  sleep(0.5 + Math.random() * 0.5)
  const pageRes = jsonPost(
    base,
    anonKey,
    session.token,
    RPC_NAMES.feed,
    feedBootstrapBody({ limit: FEED_PAGE_LIMIT, cursor: cursor, scope: scope }),
    "feed_page",
    false,
    feedExtraTags(cursor)
  )
  assertHttpOk(pageRes, "feed_page", 200, RPC_NAMES.feed)
}

/** Legacy direct mixed routes (supabase_direct). */
export function runSupabaseDirectIteration(base, anonKey, session, ctx) {
  const route = exec.vu.idInTest % 5
  if (route === 0) {
    scenarioDashboard(base, anonKey, session, ctx.paceShort)
    ctx.pace()
    scenarioFeed(base, anonKey, session, false)
  } else if (route === 1) {
    scenarioProfile(base, anonKey, session)
    ctx.pace()
    scenarioTrades(base, anonKey, session)
  } else if (route === 2) {
    scenarioCalendar(base, anonKey, session)
    ctx.pace()
    scenarioDashboardRpc(base, anonKey, session)
  } else if (route === 3) {
    scenarioFeed(base, anonKey, session, true)
    ctx.pace()
    scenarioTrades(base, anonKey, session)
  } else {
    scenarioDashboard(base, anonKey, session, ctx.paceShort)
    ctx.pace()
    scenarioProfile(base, anonKey, session)
  }
  ctx.pace()
}
